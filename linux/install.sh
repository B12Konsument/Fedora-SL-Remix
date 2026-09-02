#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -Eeuo pipefail
repository=B12Konsument/Fedora-SL-Remix
tty_path=${SL7_TTY_PATH:-/dev/tty}
prompt_output=${SL7_PROMPT_OUTPUT:-$tty_path}
bootstrap_root=

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

confirm() {
    local prompt=$1 answer input_fd
    exec {input_fd}<"$tty_path" || die 'Interactive input requires a controlling terminal.'
    while true; do
        printf '%s [Y/n]: ' "$prompt" >"$prompt_output"
        IFS= read -r -u "$input_fd" answer || die 'Interactive input requires a controlling terminal.'
        case ${answer,,} in
            ''|y|yes) exec {input_fd}<&-; return 0 ;;
            n|no) exec {input_fd}<&-; return 1 ;;
            *) printf 'Please answer y/yes or n/no.\n' >"$prompt_output" ;;
        esac
    done
}

install_bootstrap_dependencies() {
    local distribution package_manager
    local -a missing=() packages=()
    local command_name package
    for command_name in curl jq tar sha256sum stat; do
        command -v "$command_name" >/dev/null 2>&1 || missing+=("$command_name")
    done
    ((${#missing[@]})) || return 0
    [[ -r /etc/os-release ]] || die 'Fedora or Arch Linux is required.'
    # shellcheck source=/dev/null
    source /etc/os-release
    case " ${ID:-} ${ID_LIKE:-} " in
        *' fedora '*) distribution=fedora; package_manager=dnf ;;
        *' arch '*) distribution=arch; package_manager=pacman ;;
        *) die 'This bootstrap supports Fedora Linux and Arch Linux.' ;;
    esac
    for command_name in "${missing[@]}"; do
        case $command_name in
            sha256sum|stat) package=coreutils ;;
            *) package=$command_name ;;
        esac
        [[ " ${packages[*]} " == *" $package "* ]] || packages+=("$package")
    done
    printf 'Missing dependencies: %s\n' "${packages[*]}" >&2
    confirm 'Install missing dependencies?' || die 'Dependency installation was declined.'
    local -a elevate=()
    if ((EUID != 0)); then
        command -v sudo >/dev/null 2>&1 || die 'sudo is required only for package installation.'
        elevate=(sudo)
    fi
    if [[ $distribution == fedora ]]; then
        "${elevate[@]}" "$package_manager" install -y -- "${packages[@]}"
    else
        "${elevate[@]}" "$package_manager" -S --needed --noconfirm -- "${packages[@]}"
    fi
}

cleanup() {
    local status=$?
    if [[ -n $bootstrap_root && -d $bootstrap_root ]]; then
        local resolved parent
        resolved=$(realpath -- "$bootstrap_root")
        parent=$(realpath -- "${TMPDIR:-/tmp}")
        if [[ $resolved == "$parent"/sl7-bootstrap.* ]]; then
            find "$resolved" -depth -delete
        else
            printf 'WARNING: refusing to remove unexpected temporary path: %s\n' "$resolved" >&2
        fi
    fi
    return "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

if [[ ${SL7_INSTALL_LIBRARY_ONLY:-0} == 1 ]]; then
    trap - EXIT INT TERM
    return 0
fi

install_bootstrap_dependencies
bootstrap_root=$(mktemp -d "${TMPDIR:-/tmp}/sl7-bootstrap.XXXXXX")
release_json=$bootstrap_root/release.json
layout=$bootstrap_root/personalization-layout.json

printf '[Fedora SL7 Remix] Resolving the newest published release, including prereleases.\n'
curl -fsSL -H 'Accept: application/vnd.github+json' -H 'User-Agent: Fedora-SL7-Remix-Linux-Bootstrap' \
    "https://api.github.com/repos/$repository/releases?per_page=100" |
    jq -e 'map(select(.draft == false)) | first // error("no published release")' >"$release_json" ||
    die 'No published Fedora SL7 Remix release is available.'
tag=$(jq -er '.tag_name' "$release_json")

asset_field() {
    jq -er --arg name "$1" --arg field "$2" '
        [.assets[] | select(.name == $name)] as $matches |
        if ($matches | length) != 1 then error("missing or duplicate release asset")
        else $matches[0][$field] end
    ' "$release_json"
}

layout_url=$(asset_field personalization-layout.json browser_download_url) || die 'The release has no unique personalization-layout.json asset.'
curl -fsSL --output "$layout" -- "$layout_url"
[[ $(stat -c %s -- "$layout") == "$(asset_field personalization-layout.json size)" ]] || die 'The layout size does not match the release asset metadata.'
jq -e '.schema == 1 and (.linux_bundle | type == "object")' "$layout" >/dev/null || die 'The release has no supported Linux customizer metadata.'
bundle_name=$(jq -er '.linux_bundle.name' "$layout")
bundle_size=$(jq -er '.linux_bundle.size' "$layout")
bundle_sha=$(jq -er '.linux_bundle.sha256' "$layout")
entrypoint=$(jq -er '.linux_bundle.entrypoint' "$layout")
[[ $bundle_name =~ ^[A-Za-z0-9][A-Za-z0-9._-]*\.tar\.gz$ && $bundle_name != *..* ]] || die 'The Linux bundle filename is unsafe.'
[[ $bundle_size =~ ^[1-9][0-9]*$ && $bundle_sha =~ ^[0-9a-f]{64}$ ]] || die 'The Linux bundle integrity metadata is invalid.'
[[ $entrypoint == linux/new-fedora-sl7-iso.sh ]] || die 'The Linux bundle entrypoint is invalid.'
[[ $(asset_field "$bundle_name" size) == "$bundle_size" ]] || die 'The Linux bundle asset size does not match the layout.'
bundle_url=$(asset_field "$bundle_name" browser_download_url) || die 'The release has no unique Linux customizer bundle asset.'
bundle=$bootstrap_root/$bundle_name
curl -fsSL --output "$bundle" -- "$bundle_url"
[[ $(stat -c %s -- "$bundle") == "$bundle_size" ]] || die 'The downloaded Linux customizer bundle has the wrong size.'
[[ $(sha256sum -- "$bundle" | cut -d' ' -f1) == "$bundle_sha" ]] || die 'The downloaded Linux customizer bundle failed SHA-256 verification.'

expanded=$bootstrap_root/expanded
mkdir -- "$expanded"
tar -tzf "$bundle" | while IFS= read -r member; do
    [[ $member != /* && $member != ../* && $member != */../* && $member != *'/..' ]] || die 'The Linux customizer bundle contains an unsafe path.'
done
tar -tvzf "$bundle" | awk 'substr($1,1,1) != "-" && substr($1,1,1) != "d" {exit 1}' || die 'The Linux customizer bundle contains a link or special file.'
tar -xzf "$bundle" -C "$expanded" --no-same-owner --no-same-permissions
script=$expanded/$entrypoint
[[ -f $script && ! -L $script && -x $script && -f $expanded/linux/lib.sh && ! -L $expanded/linux/lib.sh ]] || die 'The Linux customizer bundle is malformed.'

SL7_BOOTSTRAP_LAYOUT=$layout "$script" --release "$tag"
