#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -Eeuo pipefail
PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
source "$PROJECT_ROOT/scripts/lib.sh"

require_command jq
require_command rg
require_command xmllint

jq -e '
  .schema == 1 and
  .fedora_release == 44 and
  (.sources | length > 0) and
  ([.sources[].id] | length == (unique | length)) and
  all(.sources[];
    (.id | type == "string" and length > 0) and
    (.kind | IN("git", "http", "oci")) and
    (.url | type == "string" and length > 0) and
    (((.ref // "") | length > 0) or ((.version // "") | length > 0)) and
    (.license | type == "string" and length > 0) and
    (.upstream_status | type == "string" and length > 0) and
    (.purpose | type == "string" and length > 0) and
    (.redistributable | type == "boolean") and
    (if .kind == "git" then
       (.ref | test("^[0-9a-f]{40}$")) and (.archive_sha256 | test("^[0-9a-f]{64}$")) and
       (if has("branch") then (.branch | length > 0) and (.fetch_depth | type == "number" and . >= 1) else true end)
     elif .kind == "http" then
       (.filename | length > 0) and (.sha256 | test("^[0-9a-f]{64}$"))
     else
       (.ref | test("^sha256:[0-9a-f]{64}$")) and (.sha256 | test("^[0-9a-f]{64}$"))
     end))
' "$SOURCE_LOCK" >/dev/null

jq -e '
  .schema == 1 and
  (.source_msi_sha256 | test("^[0-9a-f]{64}$")) and
  (.files | length == 10) and
  ([.files[].name] | length == (unique | length)) and
  all(.files[];
    (.name | type == "string" and length > 0) and
    (.size | type == "number" and . > 0) and
    (.sha256 | test("^[0-9a-f]{64}$")))
' "$PROJECT_ROOT/firmware/prohibited-content-hashes.json" >/dev/null
[[ "$(jq -r '.source_msi_sha256' "$PROJECT_ROOT/firmware/prohibited-content-hashes.json")" == \
   "$(jq -r '.sources[] | select(.id == "surface-laptop-7-msi") | .sha256' "$SOURCE_LOCK")" ]] || \
    die 'the proprietary-content denylist does not match the locked Microsoft MSI'

stock_kernel_evr="$(jq -er '.sources[] | select(.id == "fedora-kernel-distgit") | .version + "-" + .release' "$SOURCE_LOCK")"
mapfile -t stock_kernel_rpms < <(jq -r '.sources[] | select(.role? == "stock-kernel-fallback") | .filename' "$SOURCE_LOCK" | sort)
[[ ${#stock_kernel_rpms[@]} -eq 3 ]] || die 'the source lock must contain the three stock Fedora fallback-kernel RPMs'
jq -e 'all(.sources[] | select(.role? == "stock-kernel-fallback");
    (.signature_fingerprint | test("^[0-9a-f]{40}$")) and
    (.url | startswith("https://kojipkgs.fedoraproject.org/packages/kernel/") and contains("/data/signed/")))' \
    "$SOURCE_LOCK" >/dev/null
for package in kernel-modules kernel-modules-core kernel-uki-dtbloader; do
    grep -Fqx "Requires:       $package = $stock_kernel_evr" \
        "$PROJECT_ROOT/packages/sl7-support/fedora-sl7-remix-support.spec" || \
        die "$package fallback requirement does not match the source lock"
done

jq -e '
  .schema == 1 and
  (.patches | length > 0) and
  ([.patches[].id] | length == (unique | length)) and
  all(.patches[];
    (.id | length > 0) and
    (.license | type == "string" and length > 0) and
    (.purpose | type == "string" and length > 0) and
    (.upstream_status | type == "string" and length > 0) and
    ((has("path") and (.path | length > 0)) or
     (has("url") and (.url | startswith("https://")) and (.sha256 | test("^[0-9a-f]{64}$")))))
' "$PROJECT_ROOT/kernel/series.json" >/dev/null
jq -e '
  .patches[] |
  select(.id == "romulus-spi-dma-device-tree") |
  ([.include[] | select(startswith("drivers/hid/spi-hid/"))] | length) == 10 and
  (.include | index("drivers/hid/spi-hid/spi-hid-core.c") != null) and
  (.include | index("drivers/hid/spi-hid/spi-hid-of.c") != null) and
  (.include | index("drivers/hid/spi-hid/spi-hid-acpi.c") != null)
' "$PROJECT_ROOT/kernel/series.json" >/dev/null || \
    die 'the Romulus QSPI patch must include the complete integrated SPI-HID replacement'
grep -Fq 'CONFIG_SPI_HID=m' "$PROJECT_ROOT/scripts/build-kernel.sh" || \
    die 'the integrated SPI-HID module must be enabled for AArch64'
if grep -Eq 'CONFIG_SPI_HID_(ACPI|CORE|OF)=' "$PROJECT_ROOT/scripts/build-kernel.sh"; then
    die 'obsolete split SPI-HID kernel options must not be configured'
fi
grep -Fq 'required_kernel_modules=(spi-hid.ko)' "$PROJECT_ROOT/scripts/build-kernel.sh" || \
    die 'the kernel build must list the integrated SPI-HID module'
# shellcheck disable=SC2016
grep -Fq 'for module in "${required_kernel_modules[@]}"; do' "$PROJECT_ROOT/scripts/build-kernel.sh" || \
    die 'the kernel build must verify the integrated SPI-HID module'
grep -Fq '%meson -Ddebug_tools=calibrate' "$PROJECT_ROOT/packages/iptsd-sl7/iptsd-sl7.spec" || \
    die 'IPTSD must build the SL7 calibration utility'
grep -Fq '%{_bindir}/iptsd-calibrate' "$PROJECT_ROOT/packages/iptsd-sl7/iptsd-sl7.spec" || \
    die 'IPTSD must package the SL7 calibration utility'
grep -Fq "grep -Fq 'qcom,geni-spi-qspi'" "$PROJECT_ROOT/scripts/inspect-iso.sh" || \
    die 'ISO inspection must verify the Romulus QSPI controller'
grep -Fq "grep -Fq 'hid-over-spi'" "$PROJECT_ROOT/scripts/inspect-iso.sh" || \
    die 'ISO inspection must verify the Romulus SPI-HID touchpad'

jq -e '
  .schema == 1 and
  .result == "draft" and
  (.checks | length > 0) and
  all(.checks[]; IN("CI-tested", "hardware-verified", "community-verified", "untested", "known-broken"))
' "$PROJECT_ROOT/hardware-tests/template.json" >/dev/null

grep -q '^set default="0"$' "$PROJECT_ROOT/image/grub-arm.cfg.iso-template" || die 'the personalization guard must be the default GRUB entry'
grep -Fq 'sl7_personalized="0"' "$PROJECT_ROOT/image/model-selector.placeholder.cfg" || \
    die 'the base model selector must fail closed'
grep -Fq 'Personalize this base image from Windows or Linux before booting' "$PROJECT_ROOT/image/grub-arm.cfg.iso-template" || \
    die 'GRUB must explain that the base image requires personalization'
if grep -Fq 'rd.live.check' "$PROJECT_ROOT/image/grub-arm.cfg.iso-template"; then
    die 'the mutable personalization ISO must not offer the embedded media check'
fi
grep -q 'name="kernel-uki-dtbloader"' "$PROJECT_ROOT/image/sl7.xml" || die 'the image must explicitly install kernel-uki-dtbloader'
grep -Fq 'sl7-personalize-live.service' "$PROJECT_ROOT/packages/sl7-support/fedora-sl7-remix-support.spec" || \
    die 'the support RPM must include live personalization integration'
grep -Fq '/usr/libexec/sl7-apply-personalization /mnt/sysroot /run/sl7-personalization' \
    "$PROJECT_ROOT/image/root/usr/share/anaconda/post-scripts/95-sl7-personalization.ks" || \
    die 'Anaconda must persist private firmware explicitly'
grep -Fq "ValidateSet('Auto', 'Windows', 'Msi')" "$PROJECT_ROOT/windows/New-FedoraSl7Iso.ps1" || \
    die 'the stable Windows firmware-source interface is missing'
grep -Fq "ValidateSet('Auto', 'Romulus13', 'Romulus15')" "$PROJECT_ROOT/windows/New-FedoraSl7Iso.ps1" || \
    die 'the stable Windows model interface is missing'
grep -Fq 'ConditionKernelCommandLine=sl7.qemu-smoke=1' \
    "$PROJECT_ROOT/image/root/usr/lib/systemd/system/sl7-qemu-smoke-marker.service" || \
    die 'the QEMU marker must require the synthetic smoke-test kernel parameter'
grep -Fq 'set sl7_test_options="sl7.qemu-smoke=1"' "$PROJECT_ROOT/scripts/personalize-test-iso.sh" || \
    die 'the synthetic QEMU personalization must enable its userspace marker'
grep -Fq 'ConditionKernelCommandLine=!rd.live.image' \
    "$PROJECT_ROOT/image/root/usr/lib/systemd/system/sl7-kernel-default.service" || \
    die 'the installed-kernel default service must not run in the live environment'
grep -Fq "entry for entry in kernel_entries if '.sl7.' in entry" \
    "$PROJECT_ROOT/patches/kiwi/0002-prefer-sl7-kernel.patch" || \
    die 'the audited KIWI patch must prefer the Fedora SL7 live kernel'

mapfile -t shell_files < <(
    find "$PROJECT_ROOT" \
        \( -path "$PROJECT_ROOT/.build" -o -path "$PROJECT_ROOT/.git" -o -path "$PROJECT_ROOT/out" \) -prune -o \
        -type f \( -name '*.sh' -o -path "$PROJECT_ROOT/build.sh" \) -print | sort
)
for file in "${shell_files[@]}"; do
    bash -n "$file"
done

xmllint --noout "$PROJECT_ROOT/image/sl7.xml"

if command -v shellcheck >/dev/null; then
    shellcheck -x "${shell_files[@]}"
fi

if command -v rpmspec >/dev/null; then
    while IFS= read -r spec; do
        rpmspec --parse "$spec" >/dev/null
    done < <(find "$PROJECT_ROOT/packages" -type f -name '*.spec' -print | sort)
fi

language_report="$(mktemp /tmp/fedora-sl7-language.XXXXXX)"
trap 'rm -f -- "$language_report"' EXIT
non_english_terms="$(printf '\\x75\\x6e\\x64|\\x6f\\x64\\x65\\x72|\\x6e\\x69\\x63\\x68\\x74|\\x68\\x65\\x72\\x75\\x6e\\x74\\x65\\x72\\x6c\\x61\\x64\\x65\\x6e|\\x66\\x65\\x68\\x6c\\x65\\x72|\\x61\\x63\\x68\\x74\\x75\\x6e\\x67')"
if rg -n -i "\\b($non_english_terms)\\b" \
    "$PROJECT_ROOT" -g '!/.build/**' -g '!/.git/**' -g '!/out/**' \
    -g '*.md' -g '*.sh' -g '*.ps1' -g '*.psm1' -g '*.desktop' -g '*.service' -g '*.yml' \
    -g '*.json' -g '*.xml' -g '*.spec' \
    >"$language_report"; then
    cat "$language_report" >&2
    die 'repository-facing text must be English only'
fi

log 'Static validation passed'
