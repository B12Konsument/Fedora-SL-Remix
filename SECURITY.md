# Security policy

This project is experimental and does not receive security support from Fedora
or Microsoft. Fedora security updates remain important, but the custom kernel
can lag Fedora while its SL7 patch queue is rebuilt and tested.

Report vulnerabilities privately through GitHub's private vulnerability
reporting feature for this repository. Do not open a public issue for a flaw
that exposes firmware, credentials, Secure Boot material, release tokens, or
arbitrary code execution.

Public releases are built without Microsoft firmware and are scanned for known
prohibited filenames. Release checksums and source manifests are necessary but
do not replace review of the pinned upstream code.

Secure Boot is not supported in version 0.1.x. Do not import or publish personal
Secure Boot signing keys in this repository.

