#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only

set -Eeuo pipefail
PROJECT_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
source "$PROJECT_ROOT/scripts/lib.sh"

source_dir="$BUILD_ROOT/sources/fedora-kiwi-descriptions"
destination="$BUILD_ROOT/kiwi"
[[ -d "$source_dir/.git" ]] || die 'Fedora KIWI descriptions have not been fetched'
mkdir -p "$destination"
find "$destination" -depth -mindepth 1 -delete
rsync -a --exclude=.git "$source_dir/" "$destination/"

cp "$PROJECT_ROOT/image/sl7.xml" "$destination/components/sl7.xml"
cp "$PROJECT_ROOT/image/grub-arm.cfg.iso-template" "$destination/grub-arm.cfg.iso-template"
# The pinned Fedora config ends with `exit 0`. Appending after it silently
# skips all SL7 integration, including staging the patched DTBs under /boot.
python3 - "$destination/config.sh" "$PROJECT_ROOT/image/config-sl7.sh" <<'PY'
import pathlib
import re
import sys

config = pathlib.Path(sys.argv[1])
text = config.read_text()
end = re.search(r"(?m)^exit 0\s*\Z", text)
if end is None:
    sys.exit("Fedora config.sh no longer ends with exit 0; review SL7 integration")
integration = pathlib.Path(sys.argv[2]).read_text()
config.write_text(text[:end.start()] + integration + "\nexit 0\n")
PY

sed -i \
    -e 's#<specification>Fedora Linux</specification>#<specification>Fedora SL7 Remix</specification>#' \
    -e '/<include from="this:\/\/.\/components\/liveinstall.xml"\/>/a\	<include from="this://./components/sl7.xml"/>' \
    "$destination/Fedora.kiwi"

sed -i \
    -e 's/publisher="Fedora Project"/publisher="Fedora SL7 Remix contributors"/g' \
    -e 's/volid="Fedora_Linux"/volid="Fedora_SL7"/g' \
    -e 's/application_id="Fedora_Linux"/application_id="Fedora_SL7_Remix"/g' \
    "$destination/components/liveinstall.xml"

repository_file="$destination/repositories/sl7-local.xml"
cat > "$repository_file" <<EOF
<image>
    <repository type="rpm-md" alias="sl7-local" sourcetype="baseurl" priority="1">
        <source path="dir://$BUILD_ROOT/repo"/>
    </repository>
</image>
EOF
sed -i '/<include from="this:\/\/.\/repositories\/core.xml"\/>/a\	<include from="this://./repositories/sl7-local.xml"/>' "$destination/Fedora.kiwi"

xmllint --noout "$destination/Fedora.kiwi" "$destination/components/sl7.xml" "$repository_file"
