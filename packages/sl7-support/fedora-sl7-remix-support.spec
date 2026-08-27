Name:           fedora-sl7-remix-support
Version:        0.1.0
Release:        1%{?dist}
Summary:        Hardware integration and firmware assistant for Surface Laptop 7
License:        GPL-2.0-only AND CC-BY-SA-4.0
URL:            https://github.com/B12Konsument/Fedora-SL-Remix
Source0:        %{name}-%{version}.tar.gz
BuildArch:      noarch
Requires:       bash
Requires:       coreutils
Requires:       curl
Requires:       dracut
Requires:       findutils
Requires:       grubby
Requires:       jq
Requires:       msitools
Requires:       qcom-firmware-extract
Requires:       systemd
# Keep an unmodified, bootable Fedora UKI beside the patched installonly kernel.
Requires:       kernel-modules = 7.1.10-200.fc44
Requires:       kernel-modules-core = 7.1.10-200.fc44
Requires:       kernel-uki-dtbloader = 7.1.10-200.fc44
BuildRequires:  systemd-rpm-macros
%{?systemd_requires}

%description
Hardware detection, proprietary firmware extraction, kernel-default policy,
touchpad calibration, and user-facing integration for Fedora SL7 Remix.

%prep
%autosetup

%build

%install
cp -a image/root/. %{buildroot}/
install -Dm0644 sources.lock.json %{buildroot}%{_datadir}/fedora-sl7-remix/sources.lock.json
install -Dm0644 VERSION %{buildroot}%{_datadir}/fedora-sl7-remix/VERSION

%post
%systemd_post sl7-kernel-default.service sl7-qemu-smoke-marker.service

%preun
%systemd_preun sl7-kernel-default.service sl7-qemu-smoke-marker.service

%postun
%systemd_postun_with_restart sl7-kernel-default.service sl7-qemu-smoke-marker.service

%transfiletriggerin -- /boot
%{_libexecdir}/sl7-set-default-kernel || :

%transfiletriggerpostun -- /boot
%{_libexecdir}/sl7-set-default-kernel || :

%files
%license LICENSE LICENSES.md
%{_bindir}/sl7-detect
%{_bindir}/sl7-firmware
%{_bindir}/sl7-firmware-assistant
%{_libexecdir}/sl7-set-default-kernel
%{_unitdir}/sl7-kernel-default.service
%{_unitdir}/sl7-qemu-smoke-marker.service
%{_prefix}/lib/systemd/system-preset/80-fedora-sl7-remix.preset
%{_datadir}/applications/fedora-sl7-firmware.desktop
%{_datadir}/fedora-sl7-remix/
%config(noreplace) %{_sysconfdir}/dracut.conf.d/80-fedora-sl7-remix.conf
%config(noreplace) %{_sysconfdir}/issue.d/90-fedora-sl7-remix.issue
%config(noreplace) %{_sysconfdir}/iptsd.d/91-calibration-045E-0C77.conf

%changelog
* Wed Aug 26 2026 Fedora SL7 Remix contributors <noreply@example.invalid> - 0.1.0-1
- Initial hardware integration package
