#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -Eeuo pipefail
PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
source "$PROJECT_ROOT/scripts/lib.sh"

require_command git
require_command jq
require_command sha256sum

mkdir -p "$BUILD_ROOT/sources" "$BUILD_ROOT/downloads"

while IFS= read -r source_json; do
    id="$(jq -r .id <<<"$source_json")"
    kind="$(jq -r .kind <<<"$source_json")"
    redistributable="$(jq -r .redistributable <<<"$source_json")"

    if [[ "$kind" == http && "$redistributable" == false ]]; then
        log "Skipping non-redistributable source $id"
        continue
    fi

    case "$kind" in
        git)
            destination="$BUILD_ROOT/sources/$id"
            url="$(jq -r .url <<<"$source_json")"
            ref="$(jq -r .ref <<<"$source_json")"
            expected="$(jq -r .archive_sha256 <<<"$source_json")"
            if [[ ! -d "$destination/.git" ]]; then
                mkdir -p "$destination"
                git -c safe.directory="$destination" -C "$destination" init --quiet
                git -c safe.directory="$destination" -C "$destination" remote add origin "$url"
            fi
            log "Fetching $id at $ref"
            # Build directories are bind-mounted from the host and can therefore
            # have a different numeric owner in a rootless Podman container.
            # Trust only this source-lock-controlled checkout, never a wildcard.
            git_source=(git -c safe.directory="$destination" -C "$destination")
            if ! "${git_source[@]}" cat-file -e "$ref^{commit}" 2>/dev/null; then
                branch="$(jq -r '.branch // empty' <<<"$source_json")"
                if [[ -n "$branch" ]]; then
                    fetch_depth="$(jq -r '.fetch_depth // 64' <<<"$source_json")"
                    "${git_source[@]}" fetch --quiet --depth="$fetch_depth" origin "$branch"
                    "${git_source[@]}" cat-file -e "$ref^{commit}" 2>/dev/null || \
                        die "pinned commit for $id is outside the locked branch history window"
                else
                    "${git_source[@]}" fetch --quiet --depth=1 origin "$ref"
                fi
            fi
            "${git_source[@]}" checkout --quiet --force -B source-lock "$ref"
            [[ "$("${git_source[@]}" rev-parse HEAD)" == "$ref" ]] || die "unexpected commit for $id"
            actual="$("${git_source[@]}" archive --format=tar HEAD | sha256sum | cut -d' ' -f1)"
            [[ "$actual" == "$expected" ]] || die "archive hash mismatch for $id"
            ;;
        http)
            url="$(jq -r .url <<<"$source_json")"
            filename="$(jq -r .filename <<<"$source_json")"
            expected="$(jq -r .sha256 <<<"$source_json")"
            destination="$BUILD_ROOT/downloads/$filename"
            if [[ ! -f "$destination" ]]; then
                log "Downloading $id"
                curl --fail --location --retry 3 --output "$destination.partial" "$url"
                mv "$destination.partial" "$destination"
            fi
            verify_sha256 "$destination" "$expected"
            signature_fingerprint="$(jq -r '.signature_fingerprint // empty' <<<"$source_json")"
            if [[ -n "$signature_fingerprint" ]]; then
                require_command rpmkeys
                signature_report="$(rpmkeys --checksig --verbose "$destination")"
                grep -Fq "key fingerprint: $signature_fingerprint: OK" <<<"$signature_report" || \
                    die "RPM signature mismatch for $id"
            fi
            ;;
        oci)
            log "OCI source $id is pinned in build/Containerfile"
            ;;
        *) die "unsupported source kind '$kind' for $id" ;;
    esac
done < <(jq -c '.sources[]' "$SOURCE_LOCK")

log 'All selected sources match the source lock'
