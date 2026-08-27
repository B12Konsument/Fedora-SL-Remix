Name:           sl7-mac
Version:        1.0.0
Release:        1%{?dist}
Summary:        Restore Surface Laptop 7 factory radio addresses
License:        MIT
URL:            https://github.com/valeronm/sl7-mac
Source0:        %{name}-%{version}.tar.gz
BuildArch:      noarch
Requires:       bash
Requires:       bluez
Requires:       python3
Requires:       systemd
BuildRequires:  systemd-rpm-macros
%{?systemd_requires}

%description
Reads the Surface UEFI MAC address family and applies the factory Wi-Fi and
Bluetooth addresses early during boot.

%prep
%autosetup

%build

%install
install -Dm0755 sl7-mac %{buildroot}%{_bindir}/sl7-mac
install -Dm0755 mgmt-set-addr.py %{buildroot}%{_libexecdir}/sl7-mac/mgmt-set-addr.py
install -Dm0644 sl7-wifi-mac.service %{buildroot}%{_unitdir}/sl7-wifi-mac.service
install -Dm0644 sl7-bt-mac.service %{buildroot}%{_unitdir}/sl7-bt-mac.service
install -Dm0644 99-sl7-bt-mac.rules %{buildroot}%{_udevrulesdir}/99-sl7-bt-mac.rules
install -Dm0644 sl7-mac.1 %{buildroot}%{_mandir}/man1/sl7-mac.1

%post
%systemd_post sl7-wifi-mac.service

%preun
%systemd_preun sl7-wifi-mac.service

%postun
%systemd_postun_with_restart sl7-wifi-mac.service

%files
%license LICENSE
%doc README.md
%{_bindir}/sl7-mac
%{_libexecdir}/sl7-mac/
%{_unitdir}/sl7-wifi-mac.service
%{_unitdir}/sl7-bt-mac.service
%{_udevrulesdir}/99-sl7-bt-mac.rules
%{_mandir}/man1/sl7-mac.1*

%changelog
* Wed Aug 26 2026 Fedora SL7 Remix contributors <noreply@example.invalid> - 1.0.0-1
- Add Fedora packaging for the pinned upstream source

