#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -Eeuo pipefail
PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
source "$PROJECT_ROOT/scripts/lib.sh"

prepare_only=0
if [[ ${1:-} == --prepare-only ]]; then
    prepare_only=1
    shift
fi
[[ $# -eq 0 ]] || die 'usage: scripts/build-kernel.sh [--prepare-only]'

require_command fedpkg
require_command git
require_command jq
require_command rpmbuild

distgit="$BUILD_ROOT/sources/fedora-kernel-distgit"
[[ -d "$distgit/.git" ]] || die 'run scripts/fetch-sources.sh first'
kernel_ref="$(jq -er '.sources[] | select(.id == "fedora-kernel-distgit") | .ref' "$SOURCE_LOCK")"
git -C "$distgit" reset --quiet --hard "$kernel_ref"
git -C "$distgit" checkout --quiet --force -B sl7-build "$kernel_ref"
"$PROJECT_ROOT/scripts/fetch-kernel-patches.sh"

log 'Fetching Fedora kernel lookaside sources'
(
    cd "$distgit"
    fedpkg --release f44 sources
)

kernel_tar="$(find "$distgit" -maxdepth 1 -type f -name 'linux-*.tar.xz' -print -quit)"
[[ -n "$kernel_tar" ]] || die 'Fedora kernel source tarball was not downloaded'
kernel_version="$(basename "$kernel_tar" .tar.xz)"
kernel_version="${kernel_version#linux-}"

tree="$BUILD_ROOT/kernel-tree"
mkdir -p "$tree"
find "$tree" -depth -mindepth 1 -delete
tar -C "$tree" -xf "$kernel_tar"
source_tree="$tree/linux-$kernel_version"

log 'Applying the Fedora patch set before the SL7 queue'
patch -d "$source_tree" -p1 --fuzz=0 < "$distgit/patch-7.1-redhat.patch"

git -C "$source_tree" init --quiet
git -C "$source_tree" add -A
git -C "$source_tree" -c user.name='Fedora SL7 Remix' -c user.email=noreply@example.invalid commit --quiet -m 'Fedora baseline'

while IFS= read -r patch_json; do
    id="$(jq -r .id <<<"$patch_json")"
    if [[ "$(jq -r 'has("path")' <<<"$patch_json")" == true ]]; then
        patch_file="$PROJECT_ROOT/$(jq -r .path <<<"$patch_json")"
    else
        patch_file="$BUILD_ROOT/kernel-patches/$id.patch"
    fi

    include_args=()
    while IFS= read -r include; do
        include_args+=(--include="$include")
    done < <(jq -r '.include[]?' <<<"$patch_json")

    if git -C "$source_tree" apply --check "${include_args[@]}" "$patch_file"; then
        log "Applying kernel patch $id"
        git -C "$source_tree" apply --whitespace=nowarn "${include_args[@]}" "$patch_file"
    elif git -C "$source_tree" apply --reverse --check "${include_args[@]}" "$patch_file"; then
        log "Skipping $id because the exact change is already present"
    else
        die "kernel patch $id no longer applies cleanly; rebase it and update kernel/series.json"
    fi
done < <(jq -c '.patches[]' "$PROJECT_ROOT/kernel/series.json")

git -C "$source_tree" add --intent-to-add -A
git -C "$source_tree" diff --binary HEAD -- > "$distgit/linux-kernel-test.patch"
[[ -s "$distgit/linux-kernel-test.patch" ]] || die 'the generated SL7 kernel patch is empty'

grep -Fqx 'source "drivers/hid/spi-hid/Kconfig"' "$source_tree/drivers/hid/Kconfig" || \
    die 'SPI-HID is not connected to the parent Kconfig'
# The dollar sign is a literal Kbuild variable, not shell interpolation.
# shellcheck disable=SC2016
grep -Fqx 'obj-$(CONFIG_SPI_HID)		+= spi-hid/' "$source_tree/drivers/hid/Makefile" || \
    die 'SPI-HID is not connected to the parent Makefile'
grep -Fqx 'config SPI_HID' "$source_tree/drivers/hid/spi-hid/Kconfig" || \
    die 'the integrated HIDSPI v3/QSPI driver configuration is missing'
if grep -Eq '^config SPI_HID_(ACPI|CORE|OF)$' "$source_tree/drivers/hid/spi-hid/Kconfig"; then
    die 'the obsolete split SPI-HID driver remained after the Romulus QSPI patch'
fi
grep -Fqx 'spi-hid-objs := spi-hid-core.o' "$source_tree/drivers/hid/spi-hid/Makefile" || \
    die 'the integrated HIDSPI v3/QSPI module is not configured'
for obsolete_source in spi-hid-acpi.c spi-hid-of.c spi-hid.h; do
    [[ ! -e "$source_tree/drivers/hid/spi-hid/$obsolete_source" ]] || \
        die "obsolete SPI-HID source remained after the Romulus QSPI patch: $obsolete_source"
done

spi_hid_config=(
    CONFIG_SPI_HID=m
)
set_kernel_config() {
    local config_file=$1 key=$2 value=$3
    local replacement="$key=$value"
    if [[ $value == n ]]; then
        replacement="# $key is not set"
    fi
    if grep -q "^$key=" "$config_file"; then
        sed -i "s/^$key=.*/$replacement/" "$config_file"
    elif grep -q "^# $key is not set$" "$config_file"; then
        sed -i "s/^# $key is not set$/$replacement/" "$config_file"
    else
        printf '%s\n' "$replacement" >> "$config_file"
    fi
}
for config in "$distgit"/kernel-*-fedora.config; do
    if [[ $(basename "$config") == kernel-aarch64*-fedora.config ]]; then
        for option in "${spi_hid_config[@]}"; do
            key=${option%%=*}
            set_kernel_config "$config" "$key" "${option#*=}"
        done
    else
        set_kernel_config "$config" CONFIG_SPI_HID n
    fi
done

sed -i 's/^# define buildid \.local$/%define buildid .sl7.1/' "$distgit/kernel.spec"
grep -q '^%define buildid \.sl7\.1$' "$distgit/kernel.spec" || die 'could not set the SL7 kernel build ID'

if ((prepare_only)); then
    log 'Kernel source and patch queue prepared successfully'
    exit 0
fi

log 'Installing Fedora kernel build dependencies'
dnf -y builddep \
    --with=baseonly \
    --without=debug \
    --without=debuginfo \
    --without=doc \
    --without=tools \
    --without=selftests \
    "$distgit/kernel.spec"

topdir="$BUILD_ROOT/rpmbuild-kernel"
mkdir -p "$topdir"
find "$topdir" -depth -mindepth 1 -delete
mkdir -p "$topdir"/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}
log 'Building Fedora SL7 kernel RPMs; this is the longest build step'
rpmbuild -ba "$distgit/kernel.spec" \
    --target aarch64 \
    --define "_topdir $topdir" \
    --define "_sourcedir $distgit" \
    --define "_specdir $distgit" \
    --with baseonly \
    --without debug \
    --without debuginfo \
    --without doc \
    --without tools \
    --without selftests

mkdir -p "$BUILD_ROOT/rpms"
find "$topdir/RPMS" -type f -name '*.rpm' -exec cp -f -- {} "$BUILD_ROOT/rpms/" \;

required_kernel_modules=(spi-hid.ko)
for module in "${required_kernel_modules[@]}"; do
    found=0
    while IFS= read -r rpm_file; do
        # Do not use grep -q here: with pipefail, its early exit makes rpm(8)
        # receive SIGPIPE on large module packages and turns a match into a
        # false failure.
        if rpm -qlp "$rpm_file" | grep -E "/$module([.](xz|zst|gz))?$" >/dev/null; then
            found=1
            break
        fi
    done < <(find "$topdir/RPMS" -type f -name '*.rpm' -print | sort)
    ((found)) || die "built kernel RPMs do not contain $module"
done

while IFS= read -r filename; do
    stock_rpm="$BUILD_ROOT/downloads/$filename"
    [[ -f "$stock_rpm" ]] || die "stock Fedora fallback RPM is missing: $filename"
    cp -f -- "$stock_rpm" "$BUILD_ROOT/rpms/"
done < <(jq -r '.sources[] | select(.role? == "stock-kernel-fallback") | .filename' "$SOURCE_LOCK")
