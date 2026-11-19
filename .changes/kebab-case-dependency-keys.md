---
bump: patch
category: Internal
kind: tooling
---

Vendor Lute dependencies into `.lpm/` and require them through one `@lpm` alias, and ship `src/.config.luau` so a vendored copy resolves `@root` itself.
