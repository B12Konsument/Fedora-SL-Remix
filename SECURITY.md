# Security policy

This project is experimental and does not receive security support from Fedora
or Microsoft. Fedora security updates remain important, but the custom kernel
can lag Fedora while its SL7 patch queue is rebuilt and tested.

Report vulnerabilities privately through GitHub's private vulnerability
reporting feature for this repository. Do not open a public issue for a flaw
that exposes firmware, credentials, Secure Boot material, release tokens, or
arbitrary code execution.

Public personalization bases are built without Microsoft firmware and are
scanned for prohibited filenames and the known content hashes derived from the
locked MSI. The Windows tool validates release parts, the complete base, fixed
placeholders, the locked MSI, and its private output. Checksums and source
manifests do not replace review of pinned code.

Secure Boot is not supported in version 0.2.x. Do not import or publish personal
Secure Boot signing keys in this repository.
