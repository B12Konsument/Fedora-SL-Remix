#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -Eeuo pipefail
PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
source "$PROJECT_ROOT/scripts/lib.sh"

require_command rpmbuild
mkdir -p "$BUILD_ROOT/rpmbuild" "$BUILD_ROOT/rpms"
find "$BUILD_ROOT/rpmbuild" -depth -mindepth 1 -delete
find "$BUILD_ROOT/rpms" -depth -mindepth 1 -delete
mkdir -p "$BUILD_ROOT/rpmbuild"/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}
topdir="$BUILD_ROOT/rpmbuild"

make_archive() {
    local source_id=$1 prefix=$2 output=$3
    git -C "$BUILD_ROOT/sources/$source_id" archive --format=tar --prefix="$prefix/" HEAD | gzip -n > "$topdir/SOURCES/$output"
}

make_archive iptsd-sl7 iptsd-sl7-3.1.0 iptsd-sl7-3.1.0.tar.gz
make_archive sl7-mac sl7-mac-1.0.0 sl7-mac-1.0.0.tar.gz

cp "$PROJECT_ROOT/packages/iptsd-sl7/iptsd-sl7.spec" "$topdir/SPECS/"
cp "$PROJECT_ROOT/packages/sl7-mac/sl7-mac.spec" "$topdir/SPECS/"

support_archive="$topdir/SOURCES/fedora-sl7-remix-support-$(<"$PROJECT_ROOT/VERSION").tar.gz"
tar --sort=name --mtime='UTC 2026-08-26' --owner=0 --group=0 --numeric-owner \
    -C "$PROJECT_ROOT" -czf "$support_archive" \
    --transform="s,^,fedora-sl7-remix-support-$(<"$PROJECT_ROOT/VERSION")/," \
    packages/sl7-support image/root sources.lock.json VERSION LICENSE LICENSES.md
cp "$PROJECT_ROOT/packages/sl7-support/fedora-sl7-remix-support.spec" "$topdir/SPECS/"

for spec in "$topdir/SPECS"/*.spec; do
    log "Installing build dependencies for $(basename "$spec")"
    dnf -y builddep "$spec"
    rpmbuild -ba "$spec" --define "_topdir $topdir"
done

find "$topdir/RPMS" -type f -name '*.rpm' \
    ! -name '*-debuginfo-*' ! -name '*-debugsource-*' \
    -exec cp -f -- {} "$BUILD_ROOT/rpms/" \;

if [[ ${SKIP_KERNEL_BUILD:-0} != 1 ]]; then
    "$PROJECT_ROOT/scripts/build-kernel.sh"
else
    warn 'Skipping the kernel build because SKIP_KERNEL_BUILD=1'
fi
