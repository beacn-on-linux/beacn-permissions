%{!?version: %define version 1.0.0}
%{!?release: %define release 1}

Name:           beacn-permissions
Version:        %{version}
Release:        %{release}
Summary:        Required udev permissions for Beacn Devices
License:        MIT
URL:            https://github.com/beacn-on-linux/beacn-permissions
BuildArch:      noarch
Source0:        %{name}-%{version}.tar.gz

%description
Provides the required rules to udev to allow userspace access to all
currently released Beacn devices

%prep
%setup -q

%install
rm -rf $RPM_BUILD_ROOT
mkdir -p $RPM_BUILD_ROOT/etc/udev/rules.d/
install -m 644 src/50-beacn.rules $RPM_BUILD_ROOT/etc/udev/rules.d/50-beacn.rules

%files
/etc/udev/rules.d/50-beacn.rules

%post
udevadm control --reload-rules || echo "Reloading udev failed. You might need to reboot to complete installation." 1>&2
udevadm trigger || echo "Reloading udev failed. You might need to reboot to complete installation." 1>&2

%postun
# Runs after files are removed
udevadm control --reload-rules || echo "Reloading udev failed. You will need to reboot to complete uninstallation" 1>&2
udevadm trigger || echo "Reloading udev failed. You will need to reboot to complete uninstallation" 1>&2

%changelog
* Sat Sep 13 2025 Craig McLure <craig@mclure.net> - 1.0.0-1
- Initial package
