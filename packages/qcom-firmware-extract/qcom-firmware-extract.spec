Name:           qcom-firmware-extract
# Fedora 44 ships a newer, unrelated version sequence under the same package
# name.  The epoch makes this pinned and audited downstream build win package
# selection without pretending that upstream version 2 is version 18.
Epoch:          1
Version:        2
Release:        2%{?dist}
Summary:        Extract Qualcomm firmware from an existing Windows installation
License:        GPL-2.0-or-later
URL:            https://github.com/Radiicall/qcom-firmware-extract
Source0:        %{name}-%{version}.tar.gz
BuildArch:      noarch
Requires:       bash
Requires:       coreutils
Requires:       dislocker
Requires:       grep
Requires:       rpm-build
Requires:       util-linux

%description
Temporary extraction helper for device-specific Qualcomm firmware that cannot
be redistributed by this project.

%prep
%autosetup

%build

%install
install -Dm0755 qcom-firmware-extract %{buildroot}%{_bindir}/qcom-firmware-extract

%files
%license LICENSE
%doc README.md
%{_bindir}/qcom-firmware-extract

%changelog
* Fri Aug 28 2026 Fedora SL7 Remix contributors <noreply@example.invalid> - 1:2-2
- Prefer the pinned Remix build over Fedora's different version sequence

* Wed Aug 26 2026 Fedora SL7 Remix contributors <noreply@example.invalid> - 2-2
- Rebuild pinned upstream source for Fedora SL7 Remix
