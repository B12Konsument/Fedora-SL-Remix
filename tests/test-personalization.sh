#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -Eeuo pipefail
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
fixture="$(mktemp -d /tmp/sl7-personalization-test.XXXXXX)"
trap 'find "$fixture" -depth -delete' EXIT

source_root="$fixture/source"
target="$fixture/target"
mkdir -p "$source_root/firmware/qcom/x1e80100/microsoft/Romulus" "$target"
printf 'fixture-gpu\n' > "$source_root/firmware/qcom/x1e80100/microsoft/qcdxkmsuc8380.mbn"
for name in \
    adsp_dtbs.elf adspr.jsn adsps.jsn adspua.jsn battmgr.jsn \
    cdsp_dtbs.elf cdspr.jsn qcadsp8380.mbn qccdsp8380.mbn; do
    printf 'fixture-%s\n' "$name" > "$source_root/firmware/qcom/x1e80100/microsoft/Romulus/$name"
done

files_json="$fixture/files.json"
find "$source_root/firmware" -type f -printf '%P\n' | sort | while IFS= read -r relative; do
    jq -n --arg path "$relative" \
        --arg sha256 "$(sha256sum "$source_root/firmware/$relative" | cut -d' ' -f1)" \
        '{path:$path,sha256:$sha256}'
done | jq -s . > "$files_json"
jq -n --slurpfile files "$files_json" '{
  schema:1,
  model:"Romulus15",
  sku:"Surface_Laptop_7th_Edition_2037",
  firmware_source:"SyntheticTestFixture",
  files:$files[0]
}' > "$source_root/manifest.json"

SL7_SKIP_TARGET_FINALIZE=1 "$root/image/root/usr/libexec/sl7-apply-personalization" "$target" "$source_root" >/dev/null
test -s "$target/usr/lib/firmware/updates/qcom/x1e80100/microsoft/qcdxkmsuc8380.mbn"
jq -e '.model == "Romulus15" and (.files | length == 10)' \
    "$target/usr/share/fedora-sl7-remix/device.json" >/dev/null

mkdir -p "$target/boot"
printf 'synthetic kernel\n' > "$target/boot/vmlinuz-6.0.0.sl7.test"
command_log="$fixture/target-commands.log"
fake_chroot="$fixture/fake-chroot"
cat > "$fake_chroot" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
target=$1
shift
printf '%s :: %s\n' "$target" "$*" >> "$SL7_TEST_COMMAND_LOG"
if [[ ${1:-} == grubby ]]; then
    printf '/boot/vmlinuz-6.0.0.sl7.test\n'
fi
EOF
chmod +x "$fake_chroot"
SL7_CHROOT_COMMAND="$fake_chroot" SL7_TEST_COMMAND_LOG="$command_log" \
    "$root/image/root/usr/libexec/sl7-apply-personalization" "$target" "$source_root" >/dev/null
grep -Fq 'restorecon -RF' "$command_log"
grep -Fq 'dracut --regenerate-all --force' "$command_log"
grep -Fq '/usr/libexec/sl7-set-default-kernel' "$command_log"
grep -Fq 'grubby --default-kernel' "$command_log"

printf 'corrupt\n' >> "$source_root/firmware/qcom/x1e80100/microsoft/qcdxkmsuc8380.mbn"
if SL7_SKIP_TARGET_FINALIZE=1 "$root/image/root/usr/libexec/sl7-apply-personalization" "$target" "$source_root" >/dev/null 2>&1; then
    printf 'corrupt personalized firmware was accepted\n' >&2
    exit 1
fi

jq '.files[0].path = .files[1].path' "$source_root/manifest.json" > "$fixture/duplicate.json"
mv "$fixture/duplicate.json" "$source_root/manifest.json"
if SL7_SKIP_TARGET_FINALIZE=1 "$root/image/root/usr/libexec/sl7-apply-personalization" "$target" "$source_root" >/dev/null 2>&1; then
    printf 'a manifest with a duplicated required path was accepted\n' >&2
    exit 1
fi

printf 'personalization persistence tests passed\n'
