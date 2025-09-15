#!/bin/bash

# Local build script with git-based versioning
# Usage: ./build.sh [rpm|deb|both]

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[BUILD]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to generate package-compliant versions from git
generate_versions() {
    log "Generating version from git..."

    pwd
    ls -lah
    
git describe --tags --always --dirty

    if git describe --tags --exact-match HEAD >/dev/null 2>&1; then
        # Exact tag match - clean release
        GIT_VERSION=$(git describe --tags --exact-match HEAD)
        CLEAN_VERSION="${GIT_VERSION#v}"
        RPM_VERSION="$CLEAN_VERSION"
        RPM_RELEASE="1"
        DEB_VERSION="$CLEAN_VERSION"
        IS_RELEASE=true
        
        log "Building RELEASE version: $CLEAN_VERSION"
    else
        # Not on exact tag - development version
        GIT_DESC=$(git describe --tags --always --dirty 2>/dev/null || echo "0.0.0")
        
        if [[ $GIT_DESC == v*-*-g* ]]; then
            # Format: v1.2.3-5-g1a2b3c4[-dirty]
            BASE_VERSION=$(echo "$GIT_DESC" | sed 's/^v//' | sed 's/-[0-9]\+-g[a-f0-9]\+.*$//')
            COMMITS=$(echo "$GIT_DESC" | sed 's/.*-\([0-9]\+\)-g[a-f0-9]\+.*$/\1/')
            COMMIT_HASH=$(echo "$GIT_DESC" | sed 's/.*-g\([a-f0-9]\+\).*$/\1/')
            IS_DIRTY=$(echo "$GIT_DESC" | grep -q dirty && echo ".dirty" || echo "")
            
            # RPM format: version stays same, release includes commit info
            RPM_VERSION="$BASE_VERSION"
            RPM_RELEASE="0.${COMMITS}.git${COMMIT_HASH}${IS_DIRTY}"
            
            # DEB format: append to version with tilde (sorts before release)
            DEB_VERSION="${BASE_VERSION}~dev.${COMMITS}.git${COMMIT_HASH}${IS_DIRTY}"
            
        else
            # No previous tags or other format
            COMMIT_HASH=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
            IS_DIRTY=$(git diff-index --quiet HEAD -- 2>/dev/null || echo ".dirty")
            
            RPM_VERSION="0.0.0"
            RPM_RELEASE="0.git${COMMIT_HASH}${IS_DIRTY}"
            DEB_VERSION="0.0.0~git${COMMIT_HASH}${IS_DIRTY}"
        fi
        IS_RELEASE=false
        
        warn "Building DEVELOPMENT version"
    fi
    
    log "RPM Version: $RPM_VERSION-$RPM_RELEASE"
    log "DEB Version: $DEB_VERSION"
    
    # Export for use by build functions
    export RPM_VERSION RPM_RELEASE DEB_VERSION IS_RELEASE
}

# Build RPM package
build_rpm() {
    log "Building RPM package..."
    
    # Check if rpmbuild tools are available
    if ! command -v rpmbuild &> /dev/null; then
        error "rpmbuild not found."
        return 1
    fi
    
    # Setup RPM build environment
    if [ ! -d "$HOME/rpmbuild" ]; then
        log "Setting up RPM build environment..."
        rpmdev-setuptree
    fi
    
    # Copy spec file and source
    mkdir -p beacn-permissions-${RPM_VERSION}/
    cp -r src beacn-permissions-${RPM_VERSION}/
    tar czf ~/rpmbuild/SOURCES/beacn-permissions-${RPM_VERSION}.tar.gz beacn-permissions-${RPM_VERSION}

    # Build with version override
    log "Running rpmbuild..."
    rpmbuild -ba packaging/rpm/beacn-permissions.spec \
        --define "version $RPM_VERSION" \
        --define "release $RPM_RELEASE"
    
    # Find and copy the built RPM
    RPM_FILES=(~/rpmbuild/RPMS/noarch/beacn-permissions-*.rpm)
    if [ -f "${RPM_FILES[0]}" ]; then
        # Get the newest if multiple exist
        RPM_FILE=$(ls -t "${RPM_FILES[@]}" | head -1)
        cp "$RPM_FILE" ./
        RPM_FILENAME=$(basename "$RPM_FILE")
        log "RPM built successfully: $RPM_FILENAME"
    else
        error "Could not find built RPM file"
        return 1
    fi
}

# Build DEB package
build_deb() {
    log "Building DEB package..."
    
    # Check if dpkg-deb is available
    if ! command -v dpkg-deb &> /dev/null; then
        error "dpkg-deb not found."
        return 1
    fi
    
    # Clean any previous build
    rm -rf deb-build
    
    # Prepare DEB structure
    mkdir -p deb-build/etc/udev/rules.d/
    mkdir -p deb-build/DEBIAN
    
    # Copy the actual file to be packaged
    cp src/50-beacn.rules deb-build/etc/udev/rules.d/
    
    # Copy and update control file with version
    cp packaging/deb/DEBIAN/control deb-build/DEBIAN/
    sed -i "s/Version: .*/Version: $DEB_VERSION/" deb-build/DEBIAN/control
    
    # Copy other control files
    cp packaging/deb/DEBIAN/postinst deb-build/DEBIAN/
    cp packaging/deb/DEBIAN/postrm deb-build/DEBIAN/
    
    # Set permissions
    chmod 755 deb-build/DEBIAN/postinst
    chmod 755 deb-build/DEBIAN/postrm
    
    # Build DEB package
    DEB_FILENAME="beacn-permissions_${DEB_VERSION}_all.deb"
    log "Running dpkg-deb..."
    dpkg-deb --build deb-build "$DEB_FILENAME"
    
    # Clean up build directory
    rm -rf deb-build
    
    log "DEB built successfully: $DEB_FILENAME"
}

# Main execution
main() {
    local build_type="${1:-both}"
    
    log "Starting build process..."
    
    # Generate versions from git
    generate_versions

    # We should probably check for an error, and handle that instead of saying 'complete'.    
    case "$build_type" in
        "rpm")
            build_rpm
            ;;
        "deb")
            build_deb
            ;;
        "both"|"")
            build_rpm && build_deb
            ;;
        *)
            error "Unknown build type: $build_type"
            echo "Usage: $0 [rpm|deb|both]"
            exit 1
            ;;
    esac
    
    log "Build complete!"
    
    # Show what was built
    echo
    log "Built packages:"
    (ls -la *.rpm 2>/dev/null; ls -la *.deb 2>/dev/null) | grep . || warn "No packages found in current directory"
    
    if [ "$IS_RELEASE" = true ]; then
        echo
        log "This is a RELEASE build - suitable for distribution"
    else
        echo
        warn "This is a DEVELOPMENT build - not suitable for production"
    fi
}

# Run main function with all arguments
main "$@"
