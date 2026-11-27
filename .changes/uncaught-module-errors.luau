return {
	bump = "major",
	category = "Changes",
	kind = "requiring",
	flags = { "Breaking" },
	summary = "Raise a module's error without a traceback, so a caller's `xpcall` handler can read the message and stack separately.",
	body = [[
`require` no longer catches a module's error or appends a traceback to it. The error reaches the caller as the module raised it, and the failing module is still on the stack when the caller's `xpcall` handler runs:

```luau
local ok, result = xpcall(loader.require, function(err)
	return { message = err, traceback = debug.traceback(nil, 2) }
end, moduleScript)
```

A caller that used `pcall` and read the stack from the error string now gets only the message. Switch to `xpcall` and call `debug.traceback` in the handler.]],
}
