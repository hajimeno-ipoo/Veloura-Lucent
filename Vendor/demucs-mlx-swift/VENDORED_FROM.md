# Vendored source provenance

This directory is a vendored copy of `demucs-mlx-swift` used by Veloura Lucent.

- Upstream repository: <https://github.com/kylehowells/demucs-mlx-swift.git>
- Upstream commit: `c81c47178828db2d8bc66e64f80c745c64abdc94`
- Upstream Git tree: `553246ba64cb449207464ed9f761bf1fbab3022d`
- Upstream commit date: `2026-03-16T20:45:14Z`
- Imported: `2026-07-14`
- Import rule: copy the fixed checkout while excluding only `.git` and `.build`

The upstream `LICENSE` is retained unchanged. Its SHA-256 at import time is
`3271b37c55a37787ad3c5fade17a85fda5e98636f08c9e9c094591280b6a0a2e`.

## Veloura Lucent changes

- Add the public, `Sendable` `DemucsModelResolutionPolicy`.
- Preserve upstream lookup and Hub behavior as the default `.localThenHub` policy.
- Add `.localOnly`, which accepts only the exact explicit `modelDirectory` and never searches
  environment variables, caches, the current working directory, or Hugging Face.
- Add focused package tests for the resolution contract.
