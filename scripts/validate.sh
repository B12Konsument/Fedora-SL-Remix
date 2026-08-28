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

stock_kernel_evr="$(jq -er '.sources[] | select(.id == "fedora-kernel-distgit") | .version + "-" + .release' "$SOURCE_LOCK")"
mapfile -t stock_kernel_rpms < <(jq -r '.sources[] | select(.role? == "stock-kernel-fallback") | .filename' "$SOURCE_LOCK" | sort)
[[ ${#stock_kernel_rpms[@]} -eq 3 ]] || die 'the source lock must contain the three stock Fedora fallback-kernel RPMs'
jq -e 'all(.sources[] | select(.role? == "stock-kernel-fallback");
    .signature_fingerprint | test("^[0-9a-f]{40}$"))' "$SOURCE_LOCK" >/dev/null
for package in kernel-modules kernel-modules-core kernel-uki-dtbloader; do
    grep -Fqx "Requires:       $package = $stock_kernel_evr" \
        "$PROJECT_ROOT/packages/sl7-support/fedora-sl7-remix-support.spec" || \
        die "$package fallback requirement does not match the source lock"
done

grep -Fqx 'Epoch:          1' \
    "$PROJECT_ROOT/packages/qcom-firmware-extract/qcom-firmware-extract.spec" || \
    die 'the pinned qcom-firmware-extract build must supersede the Fedora version sequence'
grep -Fqx 'Requires:       qcom-firmware-extract = 1:2-2.fc44' \
    "$PROJECT_ROOT/packages/sl7-support/fedora-sl7-remix-support.spec" || \
    die 'the support package must require the audited qcom-firmware-extract build'

jq -e '
  .schema == 1 and
  (.patches | length > 0) and
  ([.patches[].id] | length == (unique | length)) and
  all(.patches[];
    (.id | length > 0) and
    (.license | type == "string" and length > 0) and
    (.upstream_status | type == "string" and length > 0) and
    ((has("path") and (.path | length > 0)) or
     (has("url") and (.url | startswith("https://")) and (.sha256 | test("^[0-9a-f]{64}$")))))
' "$PROJECT_ROOT/kernel/series.json" >/dev/null

jq -e '
  .schema == 1 and
  .result == "draft" and
  (.checks | length > 0) and
  all(.checks[]; IN("CI-tested", "hardware-verified", "community-verified", "untested", "known-broken"))
' "$PROJECT_ROOT/hardware-tests/template.json" >/dev/null

grep -q '^set default="0"$' "$PROJECT_ROOT/image/grub-arm.cfg.iso-template" || die 'automatic hardware detection must be the default GRUB entry'
grep -q 'name="kernel-uki-dtbloader"' "$PROJECT_ROOT/image/sl7.xml" || die 'the image must explicitly install kernel-uki-dtbloader'
grep -Fq "[[ \${#install_rpms[@]} -eq 10 ]]" "$PROJECT_ROOT/install.sh" || \
    die 'the existing-system installer must use the audited ten-RPM install set'
if grep -Fq "dnf install -y \"\${rpms[@]}\"" "$PROJECT_ROOT/install.sh"; then
    die 'the installer must not install every kernel build artifact from the bundle'
fi

mapfile -t shell_files < <(
    find "$PROJECT_ROOT" \
        \( -path "$PROJECT_ROOT/.build" -o -path "$PROJECT_ROOT/.git" -o -path "$PROJECT_ROOT/out" \) -prune -o \
        -type f \( -name '*.sh' -o -path "$PROJECT_ROOT/build.sh" -o -path "$PROJECT_ROOT/install.sh" \) -print | sort
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
    -g '*.md' -g '*.sh' -g '*.desktop' -g '*.service' -g '*.yml' \
    -g '*.json' -g '*.xml' -g '*.spec' \
    >"$language_report"; then
    cat "$language_report" >&2
    die 'repository-facing text must be English only'
fi

log 'Static validation passed'
