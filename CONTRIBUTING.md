# Contributing

Fedora SL7 Remix accepts narrowly scoped hardware enablement, packaging,
documentation, and test-report contributions. All repository-facing content
must be English.

Before submitting a change:

1. Run `./scripts/validate.sh`.
2. Keep proprietary firmware, MSI files, generated RPMs, ISOs, device serial
   numbers, MAC addresses, and BitLocker data out of Git.
3. Add source provenance, an immutable revision, SHA-256, license, purpose, and
   upstream status to `sources.lock.json` before consuming a new upstream. Add
   the same metadata to `kernel/series.json` for an individual kernel patch.
4. Keep the kernel queue minimal. Demonstrate that each patch is absent from
   the pinned Fedora source and remove it once equivalent code lands.
5. Use `hardware-tests/template.json` for physical-device results. Do not turn
   an untested status into a verified status without the complete checklist.
6. Explain whether a change affects the Linux base build, the fixed ISO
   personalization format, Windows extraction, live boot, or installed-system
   persistence. Format changes require matching Linux and Pester tests.

Do not rebase a failed source hash or patch automatically. An unexpected change
is a supply-chain event that requires inspection.

By contributing, you agree that original scripts are provided under
GPL-2.0-only and original documentation under CC-BY-SA-4.0. Retain upstream
SPDX identifiers and authorship on imported material.
