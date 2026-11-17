local types = require("@root/types")

type ModuleFunction = types.ModuleFunction
type LoadModule = (ModuleScript) -> ((() -> ...unknown)?, string?, (() -> ())?)

-- `debug.loadmodule` only exists behind an engine flag and errors outside of
-- RobloxScript security, so it's called through a pcall. It returns the
-- module's chunk, or nil and an error message, plus a cleanup function.
local loadmodule: LoadModule? = (debug :: any).loadmodule

--[[
	Compiles a ModuleScript with `debug.loadmodule` and returns a module
	function with the same `(script, require, _G)` signature as the loadstring
	and tmpScript paths.

	Returns `nil, nil` when `debug.loadmodule` can't be used in this context,
	and `nil, err` when the module failed to compile.
]]
local function loadWithLoadmodule(moduleScript: ModuleScript, onCleanup: (() -> ()) -> ()): (ModuleFunction?, string?)
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

	if cleanupFn then
		onCleanup(cleanupFn)
	end

	local defaultEnvironment = getfenv(moduleChunk)

	return function(script: ModuleScript, require: unknown, globals: unknown)
		-- The chunk is the module's own top-level function, so its globals are
		-- swapped out instead of being passed in as parameters.
		setfenv(
			moduleChunk,
			setmetatable({
				script = script,
				require = require,
				_G = globals,
			}, {
				__index = defaultEnvironment,
			}) :: any
		)

		return moduleChunk()
	end,
		nil
end

return loadWithLoadmodule
