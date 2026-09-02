#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -Eeuo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
fixture=$(mktemp -d "$root/.linux-customizer-test.XXXXXX")
trap 'find "$fixture" -depth -delete' EXIT

# shellcheck source=linux/lib.sh
source "$root/linux/lib.sh"

fail() {
    printf 'linux customizer test failed: %s\n' "$*" >&2
    exit 1
}

expect_failure() {
    local expected=$1
    shift
    local output
    if output=$("$@" 2>&1); then
        fail "command unexpectedly succeeded: $*"
    fi
    grep -Fqi -- "$expected" <<<"$output" || fail "failure did not contain '$expected': $output"
}

mkdir -p "$fixture/tmp" "$fixture/home" "$fixture/output"
printf 'ID=fedora\n' >"$fixture/fedora-os-release"
printf 'ID=arch\n' >"$fixture/arch-os-release"
[[ $(SL7_OS_RELEASE="$fixture/fedora-os-release" sl7_detect_distribution) == fedora ]] || fail 'Fedora detection'
[[ $(SL7_OS_RELEASE="$fixture/arch-os-release" sl7_detect_distribution) == arch ]] || fail 'Arch detection'
[[ $(sl7_dependency_package fedora msiextract) == msitools ]] || fail 'Fedora msitools mapping'
[[ $(sl7_dependency_package arch msiextract) == msitools ]] || fail 'Arch msitools mapping'
[[ $(sl7_dependency_package fedora sha256sum) == coreutils ]] || fail 'Fedora coreutils mapping'
[[ $(sl7_dependency_package arch cpio) == cpio ]] || fail 'Arch cpio mapping'

for answer in '' y yes; do
    printf '%s\n' "$answer" >"$fixture/answer"
    SL7_TTY_PATH="$fixture/answer" SL7_PROMPT_OUTPUT=/dev/null sl7_confirm 'Continue?' ||
        fail "confirmation '$answer' was not accepted"
done
for answer in n no; do
    printf '%s\n' "$answer" >"$fixture/answer"
    if SL7_TTY_PATH="$fixture/answer" SL7_PROMPT_OUTPUT=/dev/null sl7_confirm 'Continue?'; then
        fail "negative confirmation '$answer' was accepted"
    fi
done
printf 'invalid\nyes\n' >"$fixture/answer"
SL7_TTY_PATH="$fixture/answer" SL7_PROMPT_OUTPUT=/dev/null sl7_confirm 'Continue?' || fail 'confirmation retry'

printf '1\n' >"$fixture/answer"
[[ $(SL7_TTY_PATH="$fixture/answer" SL7_PROMPT_OUTPUT=/dev/null sl7_select_model) == romulus13 ]] || fail 'Romulus13 selection'
printf '2\n' >"$fixture/answer"
[[ $(SL7_TTY_PATH="$fixture/answer" SL7_PROMPT_OUTPUT=/dev/null sl7_select_model) == romulus15 ]] || fail 'Romulus15 selection'

# The bootstrap prompt must consume its controlling-terminal path, not piped stdin.
printf 'no\n' >"$fixture/answer"
if printf 'yes\n' | SL7_INSTALL_LIBRARY_ONLY=1 SL7_TTY_PATH="$fixture/answer" SL7_PROMPT_OUTPUT=/dev/null \
    bash -c 'source "$1/linux/install.sh"; confirm "Continue?"' _ "$root"; then
    fail 'the pipe bootstrap consumed stdin instead of the terminal input path'
fi

expect_failure 'model is required' "$root/linux/new-fedora-sl7-iso.sh" --non-interactive --firmware-source download
expect_failure 'Invalid model' "$root/linux/new-fedora-sl7-iso.sh" --model unknown

base_size=300000000
zero_hash=$(printf '' | sha256sum | cut -d' ' -f1)
jq -n \
    --arg base_hash "$zero_hash" --arg part_hash "$zero_hash" --arg msi_hash "$zero_hash" \
    --arg bundle_hash "$zero_hash" --argjson base_size "$base_size" '{
      schema:1,minimum_customizer_version:"0.2.5",fedora_release:44,remix_version:"0.2.5",
      source_lock_sha256:("1" * 64),
      base_iso:{name:"base.iso",size:$base_size,sha256:$base_hash,parts:[{name:"base.iso.part-000",size:$base_size,sha256:$part_hash}]},
      slots:{
        model_selector:{path:"/boot/sl7/model.cfg",offset:0,length:4096,placeholder_sha256:("2" * 64)},
        personalization:{path:"/boot/sl7/personalization.cpio",offset:4096,length:268435456,placeholder_sha256:("3" * 64)}},
      hardware:{
        Surface_Laptop_7th_Edition_2036:{model:"Romulus13",dtb:"/boot/dtb/fedora-sl7-remix/romulus13.dtb",display_inches:"13.8"},
        Surface_Laptop_7th_Edition_2037:{model:"Romulus15",dtb:"/boot/dtb/fedora-sl7-remix/romulus15.dtb",display_inches:"15"}},
      microsoft_msi:{filename:"SurfaceLaptop7.msi",version:"test",url:"https://download.microsoft.com/test/SurfaceLaptop7.msi",size:1,sha256:$msi_hash},
      linux_bundle:{name:"linux-customizer.tar.gz",size:123,sha256:$bundle_hash,minimum_customizer_version:"0.2.5",customizer_version:"0.2.5",entrypoint:"linux/new-fedora-sl7-iso.sh"}
    }' >"$fixture/layout.json"
jq -n --argjson base_size "$base_size" '{
      tag_name:"v0.2.5",draft:false,assets:[
        {name:"base.iso.part-000",size:$base_size,browser_download_url:"https://example.invalid/base"},
        {name:"linux-customizer.tar.gz",size:123,browser_download_url:"https://example.invalid/bundle"},
        {name:"personalization-layout.json",size:1,browser_download_url:"https://example.invalid/layout"}]}' >"$fixture/release.json"
sl7_validate_layout "$fixture/layout.json" "$fixture/release.json" romulus13
sl7_validate_layout "$fixture/layout.json" "$fixture/release.json" romulus15

jq '.minimum_customizer_version="9.0.0"' "$fixture/layout.json" >"$fixture/bad.json"
expect_failure 'or newer is required' sl7_validate_layout "$fixture/bad.json" "$fixture/release.json" romulus13
jq '.base_iso.parts[0].name="../unsafe"' "$fixture/layout.json" >"$fixture/bad.json"
expect_failure 'unsafe asset filename' sl7_validate_layout "$fixture/bad.json" "$fixture/release.json" romulus13
jq '.assets[0].size += 1' "$fixture/release.json" >"$fixture/bad-release.json"
expect_failure 'asset size does not match' sl7_validate_layout "$fixture/layout.json" "$fixture/bad-release.json" romulus13
jq '.slots.personalization.offset=2048' "$fixture/layout.json" >"$fixture/bad.json"
expect_failure 'overlap' sl7_validate_layout "$fixture/bad.json" "$fixture/release.json" romulus13

printf 'part fixture\n' >"$fixture/file"
file_size=$(stat -c %s "$fixture/file")
file_hash=$(sl7_sha256 "$fixture/file")
sl7_assert_file "$fixture/file" "$file_size" "$file_hash" 'ISO part'
expect_failure 'wrong size' sl7_assert_file "$fixture/file" "$((file_size + 1))" "$file_hash" 'Release asset'
expect_failure 'SHA-256' sl7_assert_file "$fixture/file" "$file_size" "$(printf 'a%.0s' {1..64})" 'ISO part'
expect_failure 'SHA-256' sl7_assert_file "$fixture/file" "$file_size" "$(printf 'b%.0s' {1..64})" 'Base ISO'
expect_failure 'SHA-256' sl7_assert_file "$fixture/file" "$file_size" "$(printf 'c%.0s' {1..64})" 'The Microsoft MSI'

firmware_root=$fixture/firmware
mkdir -p "$firmware_root/a"
expect_failure 'missing' sl7_find_firmware "$firmware_root" "$fixture/map.tsv"
for relative in "${SL7_REQUIRED_FIRMWARE[@]}"; do
    printf 'synthetic %s\n' "$relative" >"$firmware_root/a/${relative##*/}"
done
mkdir "$firmware_root/b"
cp "$firmware_root/a/qcdxkmsuc8380.mbn" "$firmware_root/b/qcdxkmsuc8380.mbn"
expect_failure 'ambiguous' sl7_find_firmware "$firmware_root" "$fixture/map.tsv"
rm "$firmware_root/b/qcdxkmsuc8380.mbn"
sl7_find_firmware "$firmware_root" "$fixture/map.tsv"
sl7_create_manifest "$(sl7_model_json romulus15)" SyntheticMsi test "$fixture/map.tsv" "$fixture/manifest.json"
sl7_create_cpio "$fixture/map.tsv" "$fixture/manifest.json" "$fixture/cpio-valid" "$fixture/valid.cpio" 1048576
mkdir "$fixture/cpio-extracted"
(cd "$fixture/cpio-extracted" && cpio -id --quiet <"$fixture/valid.cpio")
[[ -f $fixture/cpio-extracted/usr/lib/firmware/updates/qcom/x1e80100/microsoft/qcdxkmsuc8380.mbn ]] || fail 'early GPU firmware path in CPIO'
[[ -f $fixture/cpio-extracted/sl7-personalization/firmware/qcom/x1e80100/microsoft/Romulus/qccdsp8380.mbn ]] || fail 'persistent firmware path in CPIO'
jq -e '.model == "Romulus15" and .msi_version == "test" and (.files | length == 10)' \
    "$fixture/cpio-extracted/sl7-personalization/manifest.json" >/dev/null
[[ $(stat -c %a "$fixture/cpio-extracted/sl7-personalization/manifest.json") == 644 ]] || fail 'CPIO file mode'
expect_failure 'exceeds' sl7_create_cpio "$fixture/map.tsv" "$fixture/manifest.json" "$fixture/cpio-small" "$fixture/too-large.cpio" 1

sl7_create_selector "$(sl7_model_json romulus13)" "$fixture/selector13" 4096
sl7_create_selector "$(sl7_model_json romulus15)" "$fixture/selector15" 4096
[[ $(stat -c %s "$fixture/selector13") == 4096 ]] || fail 'Romulus13 selector size'
[[ $(stat -c %s "$fixture/selector15") == 4096 ]] || fail 'Romulus15 selector size'
grep -Fq 'sl7_model="Romulus13"' "$fixture/selector13" || fail 'Romulus13 profile'
grep -Fq 'sl7_dtb="/boot/dtb/fedora-sl7-remix/romulus15.dtb"' "$fixture/selector15" || fail 'Romulus15 profile'

truncate -s 16 "$fixture/slots.bin"
hash8=$(dd if="$fixture/slots.bin" bs=1 count=8 status=none | sha256sum | cut -d' ' -f1)
jq -n --arg hash "$hash8" '{slots:{model_selector:{offset:0,length:8,placeholder_sha256:$hash},personalization:{offset:8,length:8,placeholder_sha256:$hash}}}' >"$fixture/slots.json"
sl7_verify_placeholders "$fixture/slots.bin" "$fixture/slots.json"
printf x | dd of="$fixture/slots.bin" bs=1 seek=8 conv=notrunc status=none
expect_failure 'placeholder hash' sl7_verify_placeholders "$fixture/slots.bin" "$fixture/slots.json"

printf 'publish me\n' >"$fixture/atomic.partial"
sl7_publish_no_clobber "$fixture/atomic.partial" "$fixture/atomic.iso"
[[ -f $fixture/atomic.iso && ! -e $fixture/atomic.partial ]] || fail 'atomic publication'
printf 'new\n' >"$fixture/existing.partial"
expect_failure 'already exists' sl7_publish_no_clobber "$fixture/existing.partial" "$fixture/atomic.iso"
[[ $(<"$fixture/atomic.iso") == 'publish me' ]] || fail 'existing target was overwritten'

mkdir "$fixture/safe-parent" "$fixture/safe-parent/sl7-owned"
printf x >"$fixture/safe-parent/sl7-owned/file"
sl7_safe_remove_tree "$fixture/safe-parent/sl7-owned" "$fixture/safe-parent"
[[ ! -e $fixture/safe-parent/sl7-owned ]] || fail 'safe cleanup did not remove owned directory'
expect_failure 'Refusing' sl7_safe_remove_tree "$fixture/safe-parent" "$fixture/safe-parent"

# One end-to-end run uses a sparse, synthetic base and a fake extractor. No
# Microsoft material, mount, container, loop device, or emulation is involved.
e2e=$fixture/e2e
mkdir -p "$e2e/firmware" "$e2e/fakebin" "$e2e/output" "$e2e/cache" "$e2e/tmp" "$e2e/home"
for relative in "${SL7_REQUIRED_FIRMWARE[@]}"; do
    mkdir -p "$e2e/firmware/$(dirname -- "$relative")"
    printf 'synthetic e2e %s\n' "$relative" >"$e2e/firmware/$relative"
done
printf 'synthetic MSI fixture\n' >"$e2e/source.msi"
cat >"$e2e/fakebin/msiextract" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ $1 == -C ]]
destination=$2
mkdir -p "$destination"
cp -a "$SL7_TEST_EXTRACT_SOURCE"/. "$destination"/
EOF
chmod +x "$e2e/fakebin/msiextract"

truncate -s 268443648 "$e2e/base.iso"
selector_placeholder=$(dd if="$e2e/base.iso" iflag=count_bytes count=4096 status=none | sha256sum | cut -d' ' -f1)
payload_placeholder=$(dd if="$e2e/base.iso" iflag=skip_bytes,count_bytes skip=4096 count=268435456 status=none | sha256sum | cut -d' ' -f1)
base_hash=$(sl7_sha256 "$e2e/base.iso")
msi_size=$(stat -c %s "$e2e/source.msi")
msi_hash=$(sl7_sha256 "$e2e/source.msi")
printf bundle >"$e2e/linux-customizer.tar.gz"
bundle_size=$(stat -c %s "$e2e/linux-customizer.tar.gz")
bundle_hash=$(sl7_sha256 "$e2e/linux-customizer.tar.gz")
e2e_url=${e2e// /%20}
jq -n \
    --arg base_hash "$base_hash" --arg selector_hash "$selector_placeholder" --arg payload_hash "$payload_placeholder" \
    --arg msi_hash "$msi_hash" --arg bundle_hash "$bundle_hash" --argjson msi_size "$msi_size" --argjson bundle_size "$bundle_size" '{
      schema:1,minimum_customizer_version:"0.2.5",fedora_release:44,remix_version:"0.2.5",source_lock_sha256:("1"*64),
      base_iso:{name:"synthetic-base.iso",size:268443648,sha256:$base_hash,parts:[{name:"synthetic-base.part-000",size:268443648,sha256:$base_hash}]},
      slots:{model_selector:{path:"/boot/sl7/model.cfg",offset:0,length:4096,placeholder_sha256:$selector_hash},personalization:{path:"/boot/sl7/personalization.cpio",offset:4096,length:268435456,placeholder_sha256:$payload_hash}},
      hardware:{Surface_Laptop_7th_Edition_2036:{model:"Romulus13",dtb:"/boot/dtb/fedora-sl7-remix/romulus13.dtb",display_inches:"13.8"},Surface_Laptop_7th_Edition_2037:{model:"Romulus15",dtb:"/boot/dtb/fedora-sl7-remix/romulus15.dtb",display_inches:"15"}},
      microsoft_msi:{filename:"Synthetic.msi",version:"test-only",url:"https://download.microsoft.com/synthetic",size:$msi_size,sha256:$msi_hash},
      linux_bundle:{name:"linux-customizer.tar.gz",size:$bundle_size,sha256:$bundle_hash,minimum_customizer_version:"0.2.5",customizer_version:"0.2.5",entrypoint:"linux/new-fedora-sl7-iso.sh"}}
    ' >"$e2e/layout.json"
layout_size=$(stat -c %s "$e2e/layout.json")
jq -n \
    --arg base "file://$e2e_url/base.iso" --arg bundle "file://$e2e_url/linux-customizer.tar.gz" \
    --arg layout "file://$e2e_url/layout.json" --argjson bundle_size "$bundle_size" --argjson layout_size "$layout_size" '{tag_name:"v0.2.5",draft:false,assets:[
      {name:"synthetic-base.part-000",size:268443648,browser_download_url:$base},
      {name:"linux-customizer.tar.gz",size:$bundle_size,browser_download_url:$bundle},
      {name:"personalization-layout.json",size:$layout_size,browser_download_url:$layout}]}' >"$e2e/release.json"

jq '.slots.personalization.placeholder_sha256=("f"*64)' "$e2e/layout.json" >"$e2e/bad-layout.json"
expect_failure 'placeholder hash' env PATH="$e2e/fakebin:$PATH" HOME="$e2e/home" TMPDIR="$e2e/tmp" \
    XDG_CACHE_HOME="$e2e/cache" SL7_OS_RELEASE="$fixture/fedora-os-release" SL7_RELEASE_JSON="$e2e/release.json" \
    SL7_BOOTSTRAP_LAYOUT="$e2e/bad-layout.json" SL7_TEST_EXTRACT_SOURCE="$e2e/firmware" \
    "$root/linux/new-fedora-sl7-iso.sh" --non-interactive --release v0.2.5 --model romulus15 \
    --firmware-source msi --msi-path "$e2e/source.msi" --output-dir "$e2e/output" --keep-cache
if find "$e2e/output" -maxdepth 1 -name '*.partial.*' -print -quit | grep -q .; then
    fail 'failed customization left its process-owned partial ISO behind'
fi

env PATH="$e2e/fakebin:$PATH" HOME="$e2e/home" TMPDIR="$e2e/tmp" \
    XDG_CACHE_HOME="$e2e/cache" SL7_OS_RELEASE="$fixture/fedora-os-release" SL7_RELEASE_JSON="$e2e/release.json" \
    SL7_BOOTSTRAP_LAYOUT="$e2e/layout.json" SL7_TEST_EXTRACT_SOURCE="$e2e/firmware" \
    "$root/linux/new-fedora-sl7-iso.sh" --non-interactive --release v0.2.5 --model romulus15 \
    --firmware-source msi --msi-path "$e2e/source.msi" --output-dir "$e2e/output" --keep-cache >/dev/null
final_iso=$e2e/output/Fedora-SL7-Remix-44-0.2.5-Romulus15-PRIVATE.aarch64.iso
[[ -f $final_iso && -f $final_iso.sha256 && -f $final_iso.json ]] || fail 'end-to-end outputs'
(cd "$e2e/output" && sha256sum -c "$(basename -- "$final_iso").sha256" >/dev/null)
jq -e '.model == "Romulus15" and .redistributable == false and (.firmware | length == 10)' "$final_iso.json" >/dev/null

printf 'Linux customizer tests passed\n'
