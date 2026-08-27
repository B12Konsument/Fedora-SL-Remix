Name:           iptsd-sl7
Version:        3.1.0
Release:        1%{?dist}
Summary:        IPTS userspace daemon with Surface Laptop 7 fixes
License:        GPL-2.0-or-later
URL:            https://github.com/alex-lentz/iptsd
Source0:        %{name}-%{version}.tar.gz
BuildRequires:  gcc-c++
BuildRequires:  meson
BuildRequires:  cmake
BuildRequires:  cmake(CLI11)
BuildRequires:  pkgconfig(eigen3)
BuildRequires:  pkgconfig(fmt)
BuildRequires:  pkgconfig(inih)
BuildRequires:  cmake(Microsoft.GSL)
BuildRequires:  pkgconfig(spdlog)
BuildRequires:  pkgconfig(systemd)
BuildRequires:  pkgconfig(udev)
BuildRequires:  systemd-rpm-macros
Provides:       iptsd = %{version}-%{release}
Conflicts:      iptsd

%description
IPTSD processes HID touch data for Linux. This pinned fork carries physical
click handling and resume recovery used by the Surface Laptop 7 touchpad.

%prep
%autosetup

%build
%meson -Ddebug_tools=[]
%meson_build

%install
%meson_install

%check
%meson_test

%files
%license LICENSE
%doc README.md
%config(noreplace) %{_sysconfdir}/iptsd.conf
%dir %{_sysconfdir}/iptsd.d
%dir %{_datadir}/iptsd
%{_bindir}/iptsd
%{_bindir}/iptsd-check-device
%{_bindir}/iptsd-find-hidraw
%{_bindir}/iptsd-find-service
%{_bindir}/iptsd-foreach
%{_bindir}/iptsd-systemd
%{_unitdir}/iptsd@.service
%{_udevrulesdir}/50-iptsd.rules
%{_prefix}/lib/systemd/system-sleep/iptsd
%{_datadir}/iptsd/*

%changelog
* Wed Aug 26 2026 Fedora SL7 Remix contributors <noreply@example.invalid> - 3.1.0-1
- Package the pinned SL7 fork

