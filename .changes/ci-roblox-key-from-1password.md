---
bump: patch
category: Changes
---

CI now sources the Roblox Open Cloud API key from the shared Flipbook 1Password vault at run time via `load-secrets-action`, rather than from a repo-level GitHub Actions secret. No effect on the published package.
