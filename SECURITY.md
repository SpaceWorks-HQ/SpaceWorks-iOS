# Security reporting

Report a suspected vulnerability privately through this repository's
[GitHub security advisory form](https://github.com/SpaceWorks-HQ/SpaceWorks-iOS/security/advisories/new).
Private vulnerability reporting must be enabled by the repository owner before this route is
advertised as available. If GitHub does not offer that route, use an existing private channel to
the repository owner rather than posting an exploit or credentials in public issues.

Include the affected commit/build, device/OS, reproduction steps and security impact. Use synthetic
accounts and redact access/refresh tokens, device grants, passwords, evidence photos, payment
information and personal data. Do not upload production credentials or an unredacted diagnostic
archive. Public issues are appropriate for ordinary bugs that do not expose a vulnerability or data.

This repository is under development. There is no response-time or supported-version guarantee
stated here. A simulator/fixture pass or unsigned Release compile is not a signed production release
or an assurance that a deployment's backend/provider configuration is secure.

If a secret is exposed, revoke or rotate it at its authority and remove the exposed public material;
deleting a file from the latest commit alone does not remove Git history. Keep signing and provider
credentials in the owner's private configuration. Follow the deployment, privacy and real-device
gates in [RELEASE-READINESS.md](docs/RELEASE-READINESS.md).
