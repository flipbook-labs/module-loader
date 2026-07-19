---
bump: minor
category: Features
---

Add `ModuleLoader.isSandboxed(): boolean` static method for first-class sandbox detection. Code evaluated through a ModuleLoader can now call this method to detect whether it is running in a sandboxed context. This replaces the need for workarounds like checking `getmetatable(_G) ~= nil`.
