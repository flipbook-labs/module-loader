local types = require("@root/types")

type LoadModule = types.LoadModule
type ModuleFunction = types.ModuleFunction

--[[
	Compiles a ModuleScript with `debug.loadmodule` and returns a module
	function with the same `(script, require, _G)` signature as the loadstring
	and tmpScript paths, along with the cleanup function for the chunk.

	`debug.loadmodule` only exists behind an engine flag and errors outside of
	RobloxScript security, so it's called through a pcall. Returns `nil, nil`
	when it can't be used in this context, and `nil, err` when the module
	failed to compile.
]]
local function loadWithLoadmodule(
	loadmodule: LoadModule?,
	moduleScript: ModuleScript
): (ModuleFunction?, string?, (() -> ())?)
	if not loadmodule then
		return nil, nil
	end

	local ok, moduleChunk, err, cleanupFn = pcall(loadmodule, moduleScript)

	if not ok then
		return nil, nil
	end

	if not moduleChunk then
		return nil, err or `failed to load {moduleScript:GetFullName()}`
	end

	local defaultEnvironment = getfenv(moduleChunk)

	local function moduleFunction(script: ModuleScript, require: unknown, globals: unknown)
		--[[
			The other loading paths compile a wrapper that takes `script`,
			`require`, and `_G` as parameters. This chunk is the module's own
			top-level function and takes none, so they're set as globals in its
			environment instead. Any other global falls back to the chunk's
			original environment through a metatable. setfenv's type definition
			only accepts a plain table, so the environment is cast to any.
		]]
		-- lute-lint-ignore(no_any)
		local environment = setmetatable({
			script = script,
			require = require,
			_G = globals,
		}, {
			__index = defaultEnvironment,
		}) :: any
		setfenv(moduleChunk, environment)

		return moduleChunk()
	end

	return moduleFunction, nil, cleanupFn
end

return loadWithLoadmodule
