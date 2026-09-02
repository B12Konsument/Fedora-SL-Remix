#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -Eeuo pipefail
SCRIPT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=linux/lib.sh
source "$SCRIPT_ROOT/lib.sh"

release=latest
model=
firmware_source=
msi_path=
output_dir=
keep_cache=0
non_interactive=0
download_confirmed=0
work=
partial_iso=
partial_owned=0
sha_owned=0
json_owned=0

usage() {
    cat <<'EOF'
Usage: new-fedora-sl7-iso.sh [OPTIONS]

Create a private, device-specific Fedora SL7 Remix ISO without mounts,
containers, emulation, or direct access to the Surface hardware.

Options:
  --release latest|TAG              Published release to use (default: latest)
  --model romulus13|romulus15       Physical Surface Laptop 7 model
  --firmware-source download|msi    Official MSI download or verified local MSI
  --msi-path PATH                   Local checksum-locked Microsoft MSI
  --output-dir PATH                 Destination directory (default: ~/Downloads)
  --keep-cache                      Keep verified public downloads and the MSI
  --non-interactive                 Never prompt; require every decision as an option
  --help                            Show this help
EOF
}

while (($#)); do
    case $1 in
        --release|--model|--firmware-source|--msi-path|--output-dir)
            (($# >= 2)) || sl7_die "Missing value for $1."
            option=$1 value=$2
            case $option in
                --release) release=$value ;;
                --model) model=${value,,} ;;
                --firmware-source) firmware_source=${value,,} ;;
                --msi-path) msi_path=$value ;;
                --output-dir) output_dir=$value ;;
            esac
            shift 2
            ;;
        --keep-cache) keep_cache=1; shift ;;
        --non-interactive) non_interactive=1; shift ;;
        --help|-h) usage; exit 0 ;;
        *) usage >&2; sl7_die "Unknown option: $1" ;;
    esac
done

cleanup() {
    local status=$?
    if ((partial_owned)) && [[ -n $partial_iso && -f $partial_iso ]]; then
        rm -f -- "$partial_iso"
    fi
    if ((sha_owned)) && [[ -n ${final_sha:-} && -f $final_sha ]]; then
        rm -f -- "$final_sha"
    fi
    if ((json_owned)) && [[ -n ${final_json:-} && -f $final_json ]]; then
        rm -f -- "$final_json"
    fi
    if [[ -n $work && -d $work ]]; then
        sl7_safe_remove_tree "$work" "${TMPDIR:-/tmp}" || :
    fi
    if ((status != 0)); then
        printf 'No disk was partitioned and no USB device was written.\n' >&2
    fi
    return "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

[[ -z $model || $model == romulus13 || $model == romulus15 ]] || sl7_die "Invalid model '$model'."
[[ -z $firmware_source || $firmware_source == download || $firmware_source == msi ]] || {
    sl7_die "Invalid firmware source '$firmware_source'."
}
if ((non_interactive)); then
    [[ -n $model ]] || sl7_die '--model is required with --non-interactive.'
    [[ -n $firmware_source ]] || sl7_die '--firmware-source is required with --non-interactive.'
    [[ $firmware_source != msi || -n $msi_path ]] || sl7_die '--msi-path is required for --firmware-source msi.'
fi

sl7_require_dependencies "$non_interactive" curl jq sha256sum stat dd truncate df sort cp ln touch find cpio msiextract

if [[ -z $model ]]; then
    model=$(sl7_select_model) || exit
fi
model_json=$(sl7_model_json "$model") || exit

if [[ -z $firmware_source ]]; then
    if sl7_confirm 'Download the verified official Microsoft Surface MSI?'; then
        firmware_source=download
        download_confirmed=1
    else
        firmware_source=msi
        printf 'Path to the verified Microsoft Surface MSI: ' >"$SL7_PROMPT_OUTPUT"
        IFS= read -r msi_path <"$SL7_TTY_PATH" || sl7_die 'Could not read the MSI path.'
        [[ -n $msi_path ]] || sl7_die 'An MSI path is required.'
    fi
fi
[[ $firmware_source != msi || -n $msi_path ]] || sl7_die '--msi-path is required for --firmware-source msi.'

if [[ -z $output_dir ]]; then
    output_dir=${HOME:?HOME is not set}/Downloads
fi
mkdir -p -- "$output_dir"
output_dir=$(realpath -- "$output_dir")
sl7_check_free_space "$output_dir"

work=$(mktemp -d "${TMPDIR:-/tmp}/sl7-personalizer.XXXXXX")
release_json=$work/release.json
layout=$work/personalization-layout.json
sl7_log "Resolving published release '$release'."
sl7_fetch_release "$release" "$release_json"

layout_asset_url=$(sl7_asset_field "$release_json" personalization-layout.json browser_download_url) || {
    sl7_die 'The release has no unique personalization-layout.json asset.'
}
layout_asset_size=$(sl7_asset_field "$release_json" personalization-layout.json size)
if [[ -n ${SL7_BOOTSTRAP_LAYOUT:-} ]]; then
    cp -- "$SL7_BOOTSTRAP_LAYOUT" "$layout"
    [[ $(stat -c %s -- "$layout") == "$layout_asset_size" ]] || {
        sl7_die 'The bootstrap layout size does not match the release asset metadata.'
    }
else
    sl7_download "$layout_asset_url" "$layout" "$layout_asset_size"
fi
sl7_validate_layout "$layout" "$release_json" "$model"

tag=$(jq -r '.tag_name' "$release_json")
safe_tag=${tag//[^A-Za-z0-9._-]/_}
cache_parent=${XDG_CACHE_HOME:-${HOME:?HOME is not set}/.cache}/fedora-sl7-remix
cache_dir=$cache_parent/$safe_tag
mkdir -p -- "$cache_dir"
sl7_check_free_space "$cache_dir"

msi_name=$(jq -r '.microsoft_msi.filename' "$layout")
msi_size=$(jq -r '.microsoft_msi.size' "$layout")
msi_sha=$(jq -r '.microsoft_msi.sha256' "$layout")
msi_url=$(jq -r '.microsoft_msi.url' "$layout")
msi_version=$(jq -r '.microsoft_msi.version' "$layout")
if [[ $firmware_source == download ]]; then
    msi_file=$cache_dir/$msi_name
    [[ ! -L $msi_file ]] || sl7_die 'Refusing an unsafe cached MSI symlink.'
    if [[ -f $msi_file && $(stat -c %s -- "$msi_file") == "$msi_size" && $(sl7_sha256 "$msi_file") == "$msi_sha" ]]; then
        if ((non_interactive)) || sl7_confirm "Use verified cached file $msi_name?"; then
            download_confirmed=1
        else
            rm -f -- "$msi_file"
        fi
    fi
    if (( ! non_interactive && ! download_confirmed )); then
        sl7_confirm 'Download the verified official Microsoft Surface MSI?' || sl7_die 'Microsoft MSI download was declined.'
    fi
    sl7_download "$msi_url" "$msi_file" "$msi_size" "$msi_sha"
    manifest_source=MicrosoftSurfaceMsiDownload
else
    [[ -f $msi_path ]] || sl7_die 'The selected Microsoft MSI does not exist or is not a regular file.'
    msi_file=$(realpath -- "$msi_path")
    manifest_source=MicrosoftSurfaceMsiLocal
fi
sl7_assert_file "$msi_file" "$msi_size" "$msi_sha" 'The Microsoft MSI'

if (( ! non_interactive )); then
    cat >"$SL7_PROMPT_OUTPUT" <<'EOF'

The resulting ISO contains proprietary Microsoft firmware for personal use.
It must not be redistributed. Secure Boot must be disabled. No disk will be
partitioned and no USB device will be written.

EOF
    sl7_confirm 'Create the private ISO?' || sl7_die 'Private ISO creation was declined.'
fi

extracted=$work/extracted
mkdir -p -- "$extracted"
sl7_log 'Extracting the checksum-verified Microsoft MSI without root privileges.'
msiextract -C "$extracted" "$msi_file" >/dev/null
firmware_map=$work/firmware.tsv
sl7_find_firmware "$extracted" "$firmware_map"
manifest=$work/manifest.json
sl7_create_manifest "$model_json" "$manifest_source" "$msi_version" "$firmware_map" "$manifest"
cpio_file=$work/personalization.cpio
sl7_create_cpio "$firmware_map" "$manifest" "$work/cpio-root" "$cpio_file" "$(jq -r '.slots.personalization.length' "$layout")"
selector=$work/model.cfg
sl7_create_selector "$model_json" "$selector" "$(jq -r '.slots.model_selector.length' "$layout")"

remix=$(jq -r '.remix_version' "$layout")
model_name=$(jq -r '.model' <<<"$model_json")
output_name="Fedora-SL7-Remix-44-$remix-$model_name-PRIVATE.aarch64.iso"
final_iso=$output_dir/$output_name
final_sha=$final_iso.sha256
final_json=$final_iso.json
for path in "$final_iso" "$final_sha" "$final_json"; do
    [[ ! -e $path && ! -L $path ]] || sl7_die "Refusing to overwrite existing output: $(basename -- "$path")"
done
partial_iso=$(mktemp --tmpdir="$output_dir" ".$output_name.partial.XXXXXX")
partial_owned=1

sl7_log 'Downloading and verifying every firmware-free base ISO part.'
while IFS=$'\t' read -r part_name part_size part_sha; do
    part_path=$cache_dir/$part_name
    if [[ -f $part_path && $(stat -c %s -- "$part_path") == "$part_size" && $(sl7_sha256 "$part_path") == "$part_sha" ]]; then
        if ((non_interactive)) || sl7_confirm "Use verified cached file $part_name?"; then
            :
        else
            rm -f -- "$part_path"
        fi
    fi
    part_url=$(sl7_asset_field "$release_json" "$part_name" browser_download_url)
    [[ ! -L $part_path ]] || sl7_die "Refusing unsafe cached symlink: $part_name"
    sl7_download "$part_url" "$part_path" "$part_size" "$part_sha"
    cat -- "$part_path" >>"$partial_iso"
done < <(jq -r '.base_iso.parts[] | [.name,.size,.sha256] | @tsv' "$layout")

[[ $(stat -c %s -- "$partial_iso") == "$(jq -r '.base_iso.size' "$layout")" ]] || sl7_die 'The reassembled base ISO has the wrong size.'
[[ $(sl7_sha256 "$partial_iso") == "$(jq -r '.base_iso.sha256' "$layout")" ]] || sl7_die 'The reassembled base ISO failed SHA-256 verification.'
sl7_verify_placeholders "$partial_iso" "$layout"

sl7_log 'Writing and reading back the model selector and private firmware archive.'
sl7_write_slot "$partial_iso" "$(jq -r '.slots.model_selector.offset' "$layout")" \
    "$(jq -r '.slots.model_selector.length' "$layout")" "$selector"
sl7_write_slot "$partial_iso" "$(jq -r '.slots.personalization.offset' "$layout")" \
    "$(jq -r '.slots.personalization.length' "$layout")" "$cpio_file"
[[ $(stat -c %s -- "$partial_iso") == "$(jq -r '.base_iso.size' "$layout")" ]] || sl7_die 'Personalization unexpectedly changed the ISO size.'
private_sha=$(sl7_sha256 "$partial_iso")

sha_partial=$work/output.sha256
json_partial=$work/output.json
printf '%s  %s\n' "$private_sha" "$output_name" >"$sha_partial"
jq -n \
    --arg iso "$output_name" --arg sha256 "$private_sha" --arg release "$tag" \
    --arg remix "$remix" --arg model "$model_name" --arg sku "$(jq -r '.sku' <<<"$model_json")" \
    --arg source "$manifest_source" --arg version "$msi_version" \
    --slurpfile firmware "$manifest" \
    '{schema:1,iso:$iso,sha256:$sha256,release:$release,fedora_release:44,remix_version:$remix,model:$model,sku:$sku,firmware_source:$source,msi_version:$version,firmware:$firmware[0].files,redistributable:false}' >"$json_partial"

# Create no-clobber sidecars first, then make the verified ISO visible last.
(set -o noclobber; cat -- "$sha_partial" >"$final_sha") || sl7_die 'The SHA-256 output appeared before publication.'
sha_owned=1
(set -o noclobber; cat -- "$json_partial" >"$final_json") || sl7_die 'The JSON output appeared before publication.'
json_owned=1
# A hard link is an atomic no-clobber publication on the destination filesystem.
sl7_publish_no_clobber "$partial_iso" "$final_iso"
partial_owned=0
sha_owned=0
json_owned=0
[[ $(sl7_sha256 "$final_iso") == "$private_sha" ]] || sl7_die 'The atomically published ISO failed final SHA-256 verification.'

if (( ! keep_cache )); then
    sl7_safe_remove_tree "$cache_dir" "$cache_parent" || :
fi
printf '\nPrivate ISO created successfully.\n\n'
printf 'Model: %s\n' "$model_name"
printf 'Physical device: %s\n' "$(jq -r '.label' <<<"$model_json")"
printf 'Secure Boot must be disabled.\n'
printf 'This ISO contains Microsoft firmware and must not be redistributed.\n'
printf 'No disk was partitioned and no USB device was written.\n'
printf 'Output: %s\n' "$final_iso"
