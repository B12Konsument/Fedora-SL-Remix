#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

# Shared, sourceable implementation for the Linux ISO personalizer. The caller
# is responsible for enabling strict Bash mode.

SL7_REPOSITORY=${SL7_REPOSITORY:-B12Konsument/Fedora-SL-Remix}
SL7_CUSTOMIZER_VERSION=0.2.5
SL7_MODEL_SLOT_SIZE=4096
SL7_PERSONALIZATION_SLOT_SIZE=268435456
SL7_TTY_PATH=${SL7_TTY_PATH:-/dev/tty}
SL7_PROMPT_OUTPUT=${SL7_PROMPT_OUTPUT:-$SL7_TTY_PATH}

readonly SL7_REQUIRED_FIRMWARE=(
    qcom/x1e80100/microsoft/qcdxkmsuc8380.mbn
    qcom/x1e80100/microsoft/Romulus/adsp_dtbs.elf
    qcom/x1e80100/microsoft/Romulus/adspr.jsn
    qcom/x1e80100/microsoft/Romulus/adsps.jsn
    qcom/x1e80100/microsoft/Romulus/adspua.jsn
    qcom/x1e80100/microsoft/Romulus/battmgr.jsn
    qcom/x1e80100/microsoft/Romulus/cdsp_dtbs.elf
    qcom/x1e80100/microsoft/Romulus/cdspr.jsn
    qcom/x1e80100/microsoft/Romulus/qcadsp8380.mbn
    qcom/x1e80100/microsoft/Romulus/qccdsp8380.mbn
)

sl7_log() {
    printf '[Fedora SL7 Remix] %s\n' "$*"
}

sl7_die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

sl7_is_safe_basename() {
    local name=${1:-}
    [[ $name =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ && $name != *..* && $name != */* ]]
}

sl7_is_sha256() {
    [[ ${1:-} =~ ^[0-9a-f]{64}$ ]]
}

sl7_sha256() {
    sha256sum -- "$1" | cut -d' ' -f1
}

sl7_version_at_least() {
    local actual=${1#v} required=${2#v}
    local a1 a2 a3 r1 r2 r3
    [[ $actual =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]] || return 1
    a1=${BASH_REMATCH[1]} a2=${BASH_REMATCH[2]} a3=${BASH_REMATCH[3]}
    [[ $required =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]] || return 1
    r1=${BASH_REMATCH[1]} r2=${BASH_REMATCH[2]} r3=${BASH_REMATCH[3]}
    ((10#$a1 > 10#$r1)) ||
        ((10#$a1 == 10#$r1 && 10#$a2 > 10#$r2)) ||
        ((10#$a1 == 10#$r1 && 10#$a2 == 10#$r2 && 10#$a3 >= 10#$r3))
}

sl7_confirm() {
    local prompt=$1 answer input_fd
    exec {input_fd}<"$SL7_TTY_PATH" || {
        sl7_die 'Interactive input requires a controlling terminal.'
    }
    while true; do
        printf '%s [Y/n]: ' "$prompt" >"$SL7_PROMPT_OUTPUT"
        if ! IFS= read -r -u "$input_fd" answer; then
            exec {input_fd}<&-
            sl7_die 'Interactive input requires a controlling terminal. Use --non-interactive with all required options.'
        fi
        case ${answer,,} in
            ''|y|yes) exec {input_fd}<&-; return 0 ;;
            n|no) exec {input_fd}<&-; return 1 ;;
            *) printf 'Please answer y/yes or n/no.\n' >"$SL7_PROMPT_OUTPUT" ;;
        esac
    done
}

sl7_select_model() {
    local answer input_fd
    exec {input_fd}<"$SL7_TTY_PATH" || {
        sl7_die 'Interactive model selection requires a controlling terminal.'
    }
    while true; do
        cat >"$SL7_PROMPT_OUTPUT" <<'EOF'
Fedora SL7 Remix - private ISO creation

Select your physical Surface Laptop 7:

1) Surface Laptop 7, 13.8-inch - SKU 2036 - Romulus13
2) Surface Laptop 7, 15-inch   - SKU 2037 - Romulus15

EOF
        printf 'Selection [1/2]: ' >"$SL7_PROMPT_OUTPUT"
        if ! IFS= read -r -u "$input_fd" answer; then
            exec {input_fd}<&-
            sl7_die 'Interactive model selection requires a controlling terminal.'
        fi
        case $answer in
            1) exec {input_fd}<&-; printf 'romulus13\n'; return ;;
            2) exec {input_fd}<&-; printf 'romulus15\n'; return ;;
            *) printf 'Please select 1 or 2.\n' >"$SL7_PROMPT_OUTPUT" ;;
        esac
    done
}

sl7_model_json() {
    case ${1:-} in
        romulus13)
            jq -n '{key:"romulus13",model:"Romulus13",sku:"Surface_Laptop_7th_Edition_2036",sku_number:"2036",display_inches:"13.8",label:"Surface Laptop 7, 13.8-inch",selector_label:"Surface Laptop 7 13.8-inch",dtb:"/boot/dtb/fedora-sl7-remix/romulus13.dtb"}'
            ;;
        romulus15)
            jq -n '{key:"romulus15",model:"Romulus15",sku:"Surface_Laptop_7th_Edition_2037",sku_number:"2037",display_inches:"15",label:"Surface Laptop 7, 15-inch",selector_label:"Surface Laptop 7 15-inch",dtb:"/boot/dtb/fedora-sl7-remix/romulus15.dtb"}'
            ;;
        *) sl7_die "Unsupported model '${1:-}'. Expected romulus13 or romulus15." ;;
    esac
}

sl7_detect_distribution() {
    local os_release=${SL7_OS_RELEASE:-/etc/os-release} id like
    [[ -r $os_release ]] || sl7_die "Cannot read $os_release. Fedora or Arch Linux is required."
    id=$(sed -n 's/^ID=//p' "$os_release" | head -1 | tr -d '"')
    like=$(sed -n 's/^ID_LIKE=//p' "$os_release" | head -1 | tr -d '"')
    case " $id $like " in
        *' fedora '*) printf 'fedora\n' ;;
        *' arch '*) printf 'arch\n' ;;
        *) sl7_die 'Unsupported Linux distribution. This tool supports Fedora Linux and Arch Linux.' ;;
    esac
}

sl7_dependency_package() {
    local distribution=$1 command_name=$2
    case "$distribution:$command_name" in
        fedora:curl|arch:curl) printf 'curl\n' ;;
        fedora:jq|arch:jq) printf 'jq\n' ;;
        fedora:cpio|arch:cpio) printf 'cpio\n' ;;
        fedora:msiextract|arch:msiextract) printf 'msitools\n' ;;
        fedora:find) printf 'findutils\n' ;;
        arch:find) printf 'findutils\n' ;;
        fedora:sha256sum|fedora:stat|fedora:dd|fedora:truncate|fedora:df|fedora:sort|fedora:cp|fedora:ln|fedora:touch)
            printf 'coreutils\n' ;;
        arch:sha256sum|arch:stat|arch:dd|arch:truncate|arch:df|arch:sort|arch:cp|arch:ln|arch:touch)
            printf 'coreutils\n' ;;
        fedora:tar|arch:tar) printf 'tar\n' ;;
        *) sl7_die "No verified package mapping for command '$command_name' on $distribution." ;;
    esac
}

sl7_missing_packages() {
    local distribution=$1
    shift
    local command_name package
    local -A packages=()
    for command_name in "$@"; do
        command -v "$command_name" >/dev/null 2>&1 && continue
        package=$(sl7_dependency_package "$distribution" "$command_name") || return
        packages[$package]=1
    done
    ((${#packages[@]} == 0)) || printf '%s\n' "${!packages[@]}" | sort
}

sl7_install_packages() {
    local distribution=$1
    shift
    (($# > 0)) || return 0
    local -a elevate=()
    if ((EUID != 0)); then
        command -v sudo >/dev/null 2>&1 || sl7_die 'sudo is required only to install missing packages.'
        elevate=(sudo)
    fi
    case $distribution in
        fedora) "${elevate[@]}" dnf install -y -- "$@" ;;
        arch) "${elevate[@]}" pacman -S --needed --noconfirm -- "$@" ;;
        *) sl7_die "Unsupported package manager for $distribution." ;;
    esac || sl7_die 'Dependency installation failed. Install the listed packages from the official distribution repositories and retry.'
}

sl7_require_dependencies() {
    local non_interactive=$1
    shift
    local distribution
    distribution=$(sl7_detect_distribution) || return
    local -a missing=()
    mapfile -t missing < <(sl7_missing_packages "$distribution" "$@")
    ((${#missing[@]} == 0)) && return 0
    printf 'Missing dependencies: %s\n' "${missing[*]}" >&2
    if ((non_interactive)); then
        sl7_die 'Install the missing dependencies from the official distribution repositories before using --non-interactive.'
    fi
    sl7_confirm 'Install missing dependencies?' || sl7_die 'Dependency installation was declined.'
    sl7_install_packages "$distribution" "${missing[@]}"
    local command_name
    for command_name in "$@"; do
        command -v "$command_name" >/dev/null 2>&1 || sl7_die "Required command remains unavailable after installation: $command_name"
    done
}

sl7_download() {
    local url=$1 destination=$2 expected_size=${3:-} expected_sha=${4:-}
    local partial=$destination.partial actual_size actual_sha
    if [[ -f $destination && -n $expected_size && -n $expected_sha ]]; then
        actual_size=$(stat -c %s -- "$destination")
        actual_sha=$(sl7_sha256 "$destination")
        if [[ $actual_size == "$expected_size" && $actual_sha == "$expected_sha" ]]; then
            return 0
        fi
        rm -f -- "$destination"
    fi
    mkdir -p -- "$(dirname -- "$destination")"
    sl7_log "Downloading $(basename -- "$destination")."
    curl --fail --location --retry 3 --continue-at - --output "$partial" -- "$url" || {
        sl7_die "Download failed. Recoverable partial data was kept at $partial."
    }
    if [[ -n $expected_size ]]; then
        actual_size=$(stat -c %s -- "$partial")
        [[ $actual_size == "$expected_size" ]] || {
            rm -f -- "$partial"
            sl7_die "Downloaded file has the wrong size: $(basename -- "$destination")"
        }
    fi
    if [[ -n $expected_sha ]]; then
        actual_sha=$(sl7_sha256 "$partial")
        [[ $actual_sha == "$expected_sha" ]] || {
            rm -f -- "$partial"
            sl7_die "Downloaded file failed SHA-256 verification: $(basename -- "$destination")"
        }
    fi
    mv -T -- "$partial" "$destination"
}

sl7_assert_file() {
    local path=$1 expected_size=$2 expected_sha=$3 label=$4
    [[ -f $path && ! -L $path ]] || sl7_die "$label is missing or is not a regular file."
    [[ $(stat -c %s -- "$path") == "$expected_size" ]] || sl7_die "$label has the wrong size."
    [[ $(sl7_sha256 "$path") == "$expected_sha" ]] || sl7_die "$label failed SHA-256 verification."
}

sl7_fetch_release() {
    local requested=$1 destination=$2 url
    if [[ -n ${SL7_RELEASE_JSON:-} ]]; then
        cp -- "$SL7_RELEASE_JSON" "$destination"
        return
    fi
    if [[ $requested == latest ]]; then
        url="https://api.github.com/repos/$SL7_REPOSITORY/releases?per_page=100"
        curl -fsSL -H 'Accept: application/vnd.github+json' -H 'User-Agent: Fedora-SL7-Remix-Linux-Personalizer' -- "$url" |
            jq -e 'map(select(.draft == false)) | first // error("no published release")' >"$destination" ||
            sl7_die 'No published Fedora SL7 Remix release is available.'
    else
        [[ $requested =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || sl7_die '--release must be latest or a semantic tag such as v0.2.5.'
        url="https://api.github.com/repos/$SL7_REPOSITORY/releases/tags/$requested"
        curl -fsSL -H 'Accept: application/vnd.github+json' -H 'User-Agent: Fedora-SL7-Remix-Linux-Personalizer' -- "$url" >"$destination" ||
            sl7_die "Published release '$requested' was not found."
    fi
    jq -e '.draft == false and (.tag_name | type == "string") and (.assets | type == "array")' "$destination" >/dev/null ||
        sl7_die 'GitHub returned a draft or malformed release.'
}

sl7_asset_field() {
    local release_json=$1 name=$2 field=$3
    jq -er --arg name "$name" --arg field "$field" '
        [.assets[] | select(.name == $name)] as $matches |
        if ($matches | length) != 1 then error("missing or duplicate release asset")
        else $matches[0][$field] end
    ' "$release_json"
}

sl7_validate_layout() {
    local layout=$1 release_json=$2 model_key=$3
    jq -e --argjson selector_size "$SL7_MODEL_SLOT_SIZE" \
        --argjson personalization_size "$SL7_PERSONALIZATION_SLOT_SIZE" '
        .schema == 1 and .fedora_release == 44 and
        (.minimum_customizer_version | type == "string") and
        (.remix_version | type == "string" and test("^[0-9]+\\.[0-9]+\\.[0-9]+$")) and
        (.source_lock_sha256 | type == "string" and test("^[0-9a-f]{64}$")) and
        (.base_iso.name | type == "string") and
        (.base_iso.size | type == "number" and . > 0 and . <= 1099511627776 and floor == .) and
        (.base_iso.sha256 | type == "string" and test("^[0-9a-f]{64}$")) and
        (.base_iso.parts | type == "array" and length > 0) and
        all(.base_iso.parts[];
            (.name | type == "string") and (.size | type == "number" and . > 0 and floor == .) and
            (.sha256 | type == "string" and test("^[0-9a-f]{64}$"))) and
        (.slots.model_selector.path == "/boot/sl7/model.cfg") and
        (.slots.model_selector.offset | type == "number" and . >= 0 and . <= 1099511627776 and floor == .) and
        (.slots.model_selector.length == $selector_size) and
        (.slots.model_selector.placeholder_sha256 | type == "string" and test("^[0-9a-f]{64}$")) and
        (.slots.personalization.path == "/boot/sl7/personalization.cpio") and
        (.slots.personalization.offset | type == "number" and . >= 0 and . <= 1099511627776 and floor == .) and
        (.slots.personalization.length == $personalization_size) and
        (.slots.personalization.placeholder_sha256 | type == "string" and test("^[0-9a-f]{64}$")) and
        (.microsoft_msi.filename | type == "string") and
        (.microsoft_msi.version | type == "string" and length > 0) and
        (.microsoft_msi.url | type == "string") and
        (.microsoft_msi.size | type == "number" and . > 0 and floor == .) and
        (.microsoft_msi.sha256 | type == "string" and test("^[0-9a-f]{64}$")) and
        (.linux_bundle.name | type == "string") and
        (.linux_bundle.size | type == "number" and . > 0 and floor == .) and
        (.linux_bundle.sha256 | type == "string" and test("^[0-9a-f]{64}$")) and
        (.linux_bundle.customizer_version | type == "string") and
        (.linux_bundle.minimum_customizer_version | type == "string") and
        (.linux_bundle.entrypoint == "linux/new-fedora-sl7-iso.sh")
    ' "$layout" >/dev/null || sl7_die 'Release personalization layout has an unsupported schema or malformed field.'

    local name hash offset length base_size end_selector end_payload sum=0 part_size
    name=$(jq -r '.base_iso.name' "$layout")
    sl7_is_safe_basename "$name" || sl7_die 'Release layout contains an unsafe base ISO filename.'
    while IFS=$'\t' read -r name part_size hash; do
        sl7_is_safe_basename "$name" || sl7_die 'Release layout contains an unsafe asset filename.'
        sl7_is_sha256 "$hash" || sl7_die 'Release layout contains an invalid asset hash.'
        ((sum += part_size))
        [[ $(sl7_asset_field "$release_json" "$name" size) == "$part_size" ]] ||
            sl7_die "GitHub asset size does not match the layout: $name"
    done < <(jq -r '.base_iso.parts[] | [.name,.size,.sha256] | @tsv' "$layout")
    base_size=$(jq -r '.base_iso.size' "$layout")
    ((sum == base_size)) || sl7_die 'ISO part sizes do not add up to the base ISO size.'

    for name in "$(jq -r '.linux_bundle.name' "$layout")" "$(jq -r '.microsoft_msi.filename' "$layout")"; do
        sl7_is_safe_basename "$name" || sl7_die 'Release layout contains an unsafe filename.'
    done
    [[ $(jq -r '.microsoft_msi.filename' "$layout") == *.msi ]] || sl7_die 'The Microsoft MSI filename is invalid.'
    name=$(jq -r '.linux_bundle.name' "$layout")
    [[ $(sl7_asset_field "$release_json" "$name" size) == "$(jq -r '.linux_bundle.size' "$layout")" ]] ||
        sl7_die 'GitHub Linux bundle size does not match the layout.'

    [[ $(jq -r '.microsoft_msi.url' "$layout") =~ ^https://download\.microsoft\.com/ ]] ||
        sl7_die 'The Microsoft MSI URL is not an official download.microsoft.com URL.'
    hash=$(jq -r '.microsoft_msi.sha256' "$layout")
    sl7_is_sha256 "$hash" || sl7_die 'The Microsoft MSI hash is invalid.'

    local required contained release_tag remix
    required=$(jq -r '.minimum_customizer_version' "$layout")
    sl7_version_at_least "$SL7_CUSTOMIZER_VERSION" "$required" ||
        sl7_die "Customizer $required or newer is required."
    required=$(jq -r '.linux_bundle.minimum_customizer_version' "$layout")
    contained=$(jq -r '.linux_bundle.customizer_version' "$layout")
    sl7_version_at_least "$contained" "$required" || sl7_die 'Linux bundle version metadata is incompatible.'
    [[ $contained == "$SL7_CUSTOMIZER_VERSION" ]] || sl7_die 'The running customizer does not match the release bundle metadata.'
    release_tag=$(jq -r '.tag_name' "$release_json")
    remix=$(jq -r '.remix_version' "$layout")
    [[ $release_tag == "v$remix" ]] || sl7_die 'Release tag and remix version do not match.'

    offset=$(jq -r '.slots.model_selector.offset' "$layout")
    length=$(jq -r '.slots.model_selector.length' "$layout")
    end_selector=$((offset + length))
    ((end_selector <= base_size)) || sl7_die 'Model-selector slot lies outside the base ISO.'
    offset=$(jq -r '.slots.personalization.offset' "$layout")
    length=$(jq -r '.slots.personalization.length' "$layout")
    end_payload=$((offset + length))
    ((end_payload <= base_size)) || sl7_die 'Personalization slot lies outside the base ISO.'
    local selector_offset payload_offset
    selector_offset=$(jq -r '.slots.model_selector.offset' "$layout")
    payload_offset=$(jq -r '.slots.personalization.offset' "$layout")
    ! ((selector_offset < end_payload && payload_offset < end_selector)) || sl7_die 'Personalization slots overlap.'

    jq -e '
        .hardware.Surface_Laptop_7th_Edition_2036.model == "Romulus13" and
        .hardware.Surface_Laptop_7th_Edition_2036.dtb == "/boot/dtb/fedora-sl7-remix/romulus13.dtb" and
        .hardware.Surface_Laptop_7th_Edition_2036.display_inches == "13.8" and
        .hardware.Surface_Laptop_7th_Edition_2037.model == "Romulus15" and
        .hardware.Surface_Laptop_7th_Edition_2037.dtb == "/boot/dtb/fedora-sl7-remix/romulus15.dtb" and
        .hardware.Surface_Laptop_7th_Edition_2037.display_inches == "15"
    ' "$layout" >/dev/null || sl7_die 'The release has an invalid supported hardware profile.'

    local model_json sku expected_model expected_dtb
    model_json=$(sl7_model_json "$model_key") || return
    sku=$(jq -r '.sku' <<<"$model_json")
    expected_model=$(jq -r '.model' <<<"$model_json")
    expected_dtb=$(jq -r '.dtb' <<<"$model_json")
    jq -e --arg sku "$sku" --arg model "$expected_model" --arg dtb "$expected_dtb" \
        '.hardware[$sku].model == $model and .hardware[$sku].dtb == $dtb' "$layout" >/dev/null ||
        sl7_die 'The selected model is absent or has an invalid SKU-to-DTB mapping.'
}

sl7_find_firmware() {
    local root=$1 output=$2 relative name
    : >"$output"
    for relative in "${SL7_REQUIRED_FIRMWARE[@]}"; do
        name=${relative##*/}
        local -a matches=()
        mapfile -d '' -t matches < <(find "$root" -type f -iname "$name" -print0)
        ((${#matches[@]} == 1)) || {
            if ((${#matches[@]} == 0)); then
                sl7_die "Required firmware file is missing from the verified MSI: $name"
            else
                sl7_die "Required firmware file is ambiguous in the verified MSI: $name"
            fi
        }
        printf '%s\t%s\t%s\n' "$relative" "${matches[0]}" "$(sl7_sha256 "${matches[0]}")" >>"$output"
    done
}

sl7_create_manifest() {
    local model_json=$1 source=$2 msi_version=$3 firmware_map=$4 output=$5
    local files_json
    files_json=$(while IFS=$'\t' read -r relative _ hash; do
        jq -n --arg path "$relative" --arg sha256 "$hash" '{path:$path,sha256:$sha256}'
    done <"$firmware_map" | jq -s .)
    jq -n \
        --arg model "$(jq -r '.model' <<<"$model_json")" \
        --arg sku "$(jq -r '.sku' <<<"$model_json")" \
        --arg display "$(jq -r '.display_inches' <<<"$model_json")" \
        --arg source "$source" --arg version "$msi_version" --argjson files "$files_json" \
        '{schema:1,model:$model,sku:$sku,display_inches:$display,firmware_source:$source,msi_version:$version,files:$files}' >"$output"
}

sl7_create_cpio() {
    local firmware_map=$1 manifest=$2 staging=$3 output=$4 slot_size=$5
    local relative source target
    mkdir -p -- "$staging/usr/lib/firmware/updates/qcom/x1e80100/microsoft" \
        "$staging/sl7-personalization/firmware" "$staging/sl7-personalization"
    while IFS=$'\t' read -r relative source _; do
        target="$staging/sl7-personalization/firmware/$relative"
        mkdir -p -- "$(dirname -- "$target")"
        cp -- "$source" "$target"
    done <"$firmware_map"
    source=$(awk -F '\t' '$1 == "qcom/x1e80100/microsoft/qcdxkmsuc8380.mbn" {print $2}' "$firmware_map")
    cp -- "$source" "$staging/usr/lib/firmware/updates/qcom/x1e80100/microsoft/qcdxkmsuc8380.mbn"
    cp -- "$manifest" "$staging/sl7-personalization/manifest.json"
    find "$staging" -type d -exec chmod 0755 {} +
    find "$staging" -type f -exec chmod 0644 {} +
    find "$staging" -exec touch -h -d '@0' {} +
    (
        cd "$staging" || exit
        find . -mindepth 1 -printf '%P\0' | sort -z |
            cpio --null --create --format=newc --owner=0:0 --reproducible --quiet
    ) >"$output"
    (( $(stat -c %s -- "$output") < slot_size )) || sl7_die 'The private firmware archive exceeds the reserved ISO slot.'
}

sl7_create_selector() {
    local model_json=$1 output=$2 length=$3 text_size
    {
        printf '# FEDORA_SL7_MODEL_SLOT_V1\n'
        printf 'set sl7_personalized="1"\n'
        printf 'set sl7_model="%s"\n' "$(jq -r '.model' <<<"$model_json")"
        printf 'set sl7_model_label="%s"\n' "$(jq -r '.selector_label' <<<"$model_json")"
        printf 'set sl7_dtb="%s"\n' "$(jq -r '.dtb' <<<"$model_json")"
    } >"$output"
    text_size=$(stat -c %s -- "$output")
    ((text_size <= length)) || sl7_die 'The model selector exceeds its reserved ISO slot.'
    dd if=/dev/zero bs=1 count=$((length - text_size)) status=none | tr '\0' ' ' >>"$output"
}

sl7_segment_sha256() {
    local file=$1 offset=$2 length=$3
    dd if="$file" iflag=skip_bytes,count_bytes skip="$offset" count="$length" status=none | sha256sum | cut -d' ' -f1
}

sl7_verify_placeholders() {
    local iso=$1 layout=$2 slot offset length expected actual
    for slot in model_selector personalization; do
        offset=$(jq -r ".slots.$slot.offset" "$layout")
        length=$(jq -r ".slots.$slot.length" "$layout")
        expected=$(jq -r ".slots.$slot.placeholder_sha256" "$layout")
        actual=$(sl7_segment_sha256 "$iso" "$offset" "$length")
        [[ $actual == "$expected" ]] || sl7_die "The base ISO placeholder hash is wrong for slot '$slot'."
    done
}

sl7_write_slot() {
    local iso=$1 offset=$2 length=$3 source=$4 padded expected actual source_size
    source_size=$(stat -c %s -- "$source")
    ((source_size <= length)) || sl7_die 'Personalization data does not fit its reserved ISO slot.'
    padded=$(mktemp "${TMPDIR:-/tmp}/sl7-slot.XXXXXX")
    cp -- "$source" "$padded"
    truncate -s "$length" -- "$padded"
    expected=$(sl7_sha256 "$padded")
    dd if="$padded" of="$iso" oflag=seek_bytes seek="$offset" conv=notrunc status=none
    actual=$(sl7_segment_sha256 "$iso" "$offset" "$length")
    rm -f -- "$padded"
    [[ $actual == "$expected" ]] || sl7_die 'Read-back verification failed for an ISO personalization slot.'
}

sl7_check_free_space() {
    local path=$1 required=$((10 * 1024 * 1024 * 1024)) available
    available=$(df -PB1 -- "$path" | awk 'NR == 2 {print $4}')
    [[ $available =~ ^[0-9]+$ ]] || sl7_die "Could not determine free space for $path."
    ((available >= required)) || sl7_die "At least 10 GiB free space is required on the filesystem containing $path."
}

sl7_safe_remove_tree() {
    local path=$1 expected_parent=$2 resolved parent
    [[ -e $path ]] || return 0
    resolved=$(realpath -- "$path")
    parent=$(realpath -- "$expected_parent")
    [[ $resolved != "$parent" && $(dirname -- "$resolved") == "$parent" ]] ||
        sl7_die "Refusing to remove unexpected temporary path: $resolved"
    find "$resolved" -depth -delete
}


sl7_publish_no_clobber() {
    local partial=$1 final=$2
    [[ $(dirname -- "$partial") == "$(dirname -- "$final")" ]] ||
        sl7_die 'The partial and final ISO must be on the same filesystem path.'
    [[ ! -e $final && ! -L $final ]] || sl7_die 'The final ISO already exists.'
    ln -- "$partial" "$final" || sl7_die 'Atomic no-clobber publication failed.'
    rm -f -- "$partial"
}
