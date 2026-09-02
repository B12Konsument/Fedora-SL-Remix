#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -Eeuo pipefail
PROJECT_ROOT=/workspace
source "$PROJECT_ROOT/scripts/lib.sh"

[[ "$(uname -m)" == aarch64 ]] || die 'the build container is not running as AArch64'
[[ ${BUILD_PHASE:-all} =~ ^(all|iso)$ ]] || die 'invalid BUILD_PHASE'

"$PROJECT_ROOT/scripts/validate.sh"

case ${BUILD_PHASE:-all} in
    all)
        "$PROJECT_ROOT/scripts/fetch-sources.sh"

        # The project directory is bind-mounted into a rootless Podman container.  A
        # source checkout can consequently have an unmapped numeric owner.  Register
        # only the Git checkouts explicitly listed in the verified source lock, so
        # downstream packaging tools (which invoke Git themselves) can use them.
        while IFS= read -r source_id; do
            git config --global --add safe.directory "$BUILD_ROOT/sources/$source_id"
        done < <(jq -r '.sources[] | select(.kind == "git") | .id' "$SOURCE_LOCK")

        "$PROJECT_ROOT/scripts/build-rpms.sh"

        mkdir -p "$BUILD_ROOT/repo"
        find "$BUILD_ROOT/repo" -depth -mindepth 1 -delete
        cp "$BUILD_ROOT/rpms"/*.rpm "$BUILD_ROOT/repo/"
        createrepo_c --database "$BUILD_ROOT/repo"
        ;;
    iso)
        [[ -f "$BUILD_ROOT/repo/repodata/repomd.xml" ]] || \
            die 'cannot resume: the validated local RPM repository is missing'
        for rpm_pattern in \
            'fedora-sl7-remix-support-*.rpm' \
            'iptsd-sl7-*.rpm' \
            'sl7-mac-*.rpm' \
            'kernel-*.sl7.*.aarch64.rpm'; do
            compgen -G "$BUILD_ROOT/repo/$rpm_pattern" >/dev/null || \
                die "cannot resume: local RPM repository lacks $rpm_pattern"
        done
        log 'Resuming from the validated local RPM repository'
        ;;
esac

final_iso="$BUILD_ROOT/Fedora-SL7-Remix-44-${BUILD_VERSION:-0.2.3}-base.aarch64.iso"
reuse_iso=0
if [[ ${BUILD_PHASE:-all} == iso && -s "$final_iso" ]]; then
    reuse_iso=1
    log "Reusing the completed ISO checkpoint: $final_iso"
fi

if ((reuse_iso == 0)); then
    "$PROJECT_ROOT/scripts/prepare-kiwi.sh"
    bash "$PROJECT_ROOT/scripts/patch-kiwi-efi-sync.sh"

    kiwi_output="$BUILD_ROOT/kiwi-output"
    mkdir -p "$kiwi_output"
    find "$kiwi_output" -depth -mindepth 1 -delete
    log 'Building the Fedora 44 KDE AArch64 live image with KIWI'
    (
        cd "$BUILD_ROOT/kiwi"
        ./kiwi-build \
            --kiwi-description-dir="$BUILD_ROOT/kiwi" \
            --kiwi-file=Fedora.kiwi \
            --output-dir="$kiwi_output/result" \
            --image-type=iso \
            --image-profile=KDE-Desktop-Live \
            --image-release="${BUILD_VERSION:-0.2.3}"
    )

    iso="$(find "$kiwi_output" -type f -name '*.iso' -print -quit)"
    [[ -n "$iso" ]] || die 'KIWI completed without producing an ISO'
    "$PROJECT_ROOT/scripts/prepare-personalization-base.sh" "$iso" "$final_iso"
fi

"$PROJECT_ROOT/scripts/inspect-iso.sh" "$final_iso" --base
layout="$BUILD_ROOT/personalization-layout.json"
"$PROJECT_ROOT/scripts/generate-personalization-layout.sh" "$final_iso" "$layout"

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
"$PROJECT_ROOT/scripts/package-release.sh" "$final_iso" "$layout" "$artifact_stage"
cp -f -- "$artifact_stage"/* /output/

log 'The personalization-base ISO and all build manifests were created successfully'
