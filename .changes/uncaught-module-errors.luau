return {
	bump = "major",
	category = "Changes",
	kind = "requiring",
	flags = { "Breaking" },
	summary = "Raise a module's error without a traceback, and add `getLastError` to read the stack separately.",
	body = [[
`require` raises a module's error exactly as the module raised it, instead of appending a traceback to the message. The loader records the stack where the module failed, and `loader.getLastError()` returns it:

```luau
local ok, err = pcall(loader.require, moduleScript)
if not ok then
	local lastError = loader.getLastError()
	print(err) -- the module's message on its own
	print(lastError and lastError.traceback)
end
```

A caller that read the stack from the error string now gets only the message, so read `getLastError().traceback` instead.]],
}
