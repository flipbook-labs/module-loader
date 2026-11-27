--[=[
	Detects whether the code calling this function is running in a ModuleLoader sandbox.

	When a module is evaluated through a loader, it receives a proxy global
	environment (`_G`). Code running in that environment can call this function
	to detect if it is sandboxed. This is useful for modules that need to behave
	differently when loaded through a loader versus when loaded with native `require()`.

	Natively-required ModuleLoader always returns false, since it sees the real
	global environment without the sandbox marker. When called from code evaluated
	through a loader, this function returns true.

	```lua
	local ModuleLoader = require(ReplicatedStorage.Packages.ModuleLoader)

	if ModuleLoader.isSandboxed() then
		print("Running in a sandbox!")
	else
		print("Running natively")
	end
	```

	@function isSandboxed
	@within ModuleLoader
	@return boolean
]=]
local function isSandboxed(): boolean
	return _G.__MODULE_LOADER_SANDBOX__ ~= nil
end

return isSandboxed
