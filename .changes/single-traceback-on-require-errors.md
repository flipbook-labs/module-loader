---
bump: patch
category: Fixes
kind: requiring
---

An error raised inside a chain of requires now carries one stack traceback. Each module in the chain used to append the full stack again, so the message grew with every level.
