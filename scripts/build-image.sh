#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -Eeuo pipefail
PROJECT_ROOT=/workspace
source "$PROJECT_ROOT/scripts/lib.sh"

[[ "$(uname -m)" == aarch64 ]] || die 'the build container is not running as AArch64'
[[ ${FIRMWARE_MODE:-redistributable} =~ ^(redistributable|download|local)$ ]] || die 'invalid FIRMWARE_MODE'

"$PROJECT_ROOT/scripts/validate.sh"
if [[ ${FIRMWARE_MODE:-redistributable} == download ]]; then
    "$PROJECT_ROOT/scripts/fetch-sources.sh" --include-proprietary
else
    "$PROJECT_ROOT/scripts/fetch-sources.sh"
fi
"$PROJECT_ROOT/scripts/build-rpms.sh"

mkdir -p "$BUILD_ROOT/repo"
find "$BUILD_ROOT/repo" -depth -mindepth 1 -delete
cp "$BUILD_ROOT/rpms"/*.rpm "$BUILD_ROOT/repo/"
createrepo_c --database "$BUILD_ROOT/repo"

"$PROJECT_ROOT/scripts/prepare-kiwi.sh"

case ${FIRMWARE_MODE:-redistributable} in
    download)
        msi="$BUILD_ROOT/downloads/$(jq -r '.sources[] | select(.id == "surface-laptop-7-msi") | .filename' "$SOURCE_LOCK")"
        ;;
    local)
        msi=${FIRMWARE_SOURCE:?FIRMWARE_SOURCE is required for local mode}
        ;;
    redistributable)
        msi=
        ;;
esac

if [[ -n "$msi" ]]; then
    warn 'Building a private image with proprietary Microsoft firmware; do not redistribute it'
    SL7_SOURCE_LOCK="$SOURCE_LOCK" \
    SL7_FIRMWARE_ROOT="$BUILD_ROOT/kiwi/root/usr/lib/firmware/updates/qcom/x1e80100/microsoft" \
        "$PROJECT_ROOT/image/root/usr/bin/sl7-firmware" install --msi "$msi"
fi

kiwi_output="$BUILD_ROOT/kiwi-output"
mkdir -p "$kiwi_output"
find "$kiwi_output" -depth -mindepth 1 -delete
log 'Building the Fedora 44 KDE AArch64 live image with KIWI'
"$BUILD_ROOT/kiwi/kiwi-build" \
    --kiwi-description-dir="$BUILD_ROOT/kiwi" \
    --kiwi-file=Fedora.kiwi \
    --output-dir="$kiwi_output/result" \
    --image-type=iso \
    --image-profile=KDE-Desktop-Live \
    --image-release="${BUILD_VERSION:-0.1.0}"

iso="$(find "$kiwi_output" -type f -name '*.iso' -print -quit)"
[[ -n "$iso" ]] || die 'KIWI completed without producing an ISO'
final_iso="$BUILD_ROOT/Fedora-SL7-Remix-44-${BUILD_VERSION:-0.1.0}.aarch64.iso"
cp "$iso" "$final_iso"

if [[ ${FIRMWARE_MODE:-redistributable} == redistributable ]]; then
    "$PROJECT_ROOT/scripts/inspect-iso.sh" "$final_iso" --public
else
    "$PROJECT_ROOT/scripts/inspect-iso.sh" "$final_iso" --private
fi

artifact_stage="$BUILD_ROOT/artifacts"
mkdir -p "$artifact_stage"
find "$artifact_stage" -depth -mindepth 1 -delete
rpm -qp --qf '%{NAME} %{EPOCHNUM}:%{VERSION}-%{RELEASE}.%{ARCH}\n' "$BUILD_ROOT/repo"/*.rpm | sort > "$artifact_stage/RPM-MANIFEST.txt"
jq -n --slurpfile sources "$SOURCE_LOCK" --slurpfile kernel "$PROJECT_ROOT/kernel/series.json" \
    '{schema:1,sources:$sources[0],kernel_patch_series:$kernel[0]}' > "$artifact_stage/SOURCE-MANIFEST.json"
jq -n --slurpfile sources "$SOURCE_LOCK" --slurpfile kernel "$PROJECT_ROOT/kernel/series.json" '{
  schema:1,
  sources:[$sources[0].sources[] | {id,license,upstream_status,redistributable,purpose,url,ref,sha256,archive_sha256}],
  kernel_patches:[$kernel[0].patches[] | {id,license,upstream_status,url,path,sha256}]
}' > "$artifact_stage/LICENSE-REPORT.json"
"$PROJECT_ROOT/scripts/create-sbom.sh" "$BUILD_ROOT/repo" "$artifact_stage/Fedora-SL7-Remix.spdx.json"
"$PROJECT_ROOT/scripts/package-release.sh" "$final_iso" "$artifact_stage"
cp -f -- "$artifact_stage"/* /output/

log 'The ISO and all build manifests were created successfully'
