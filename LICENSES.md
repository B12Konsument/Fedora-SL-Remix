# License inventory

| Material | License | Distribution policy |
| --- | --- | --- |
| Original shell and PowerShell scripts, RPM integration, and local kernel rebase | GPL-2.0-only | Included |
| Original Markdown documentation and hardware report schema | CC-BY-SA-4.0 | Included |
| Fedora KIWI descriptions | GPL-2.0-or-later | Fetched at build time |
| Linux/Fedora kernel source and kernel-derived patches | GPL-2.0-only with per-file exceptions | Fetched at build time; source manifest retained |
| IPTSD SL7 fork | GPL-2.0-or-later | Packaged from pinned source |
| sl7-mac | MIT | Packaged from pinned source |
| Surface Laptop 7 community notes | NOASSERTION | Used as research provenance, not packaged |
| Microsoft Surface MSI and extracted files | Microsoft terms; not granted by this project | Extracted on the user's Windows system only; prohibited in public artifacts |

`firmware/prohibited-content-hashes.json` contains only filenames, sizes, and
cryptographic hashes derived from the locked MSI for leakage detection; it
does not contain Microsoft firmware.

`sources.lock.json` and `kernel/series.json` are the authoritative
machine-readable lists of URLs, revisions, hashes, purpose, upstream status,
and redistribution policy. Upstream archives include their own full license
texts and SPDX declarations.

Fedora, Microsoft, Surface, Snapdragon, and other marks belong to their
respective owners. “Fedora SL7 Remix” denotes an unofficial Fedora Remix, not an
official Fedora or Microsoft product.
