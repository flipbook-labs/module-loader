local createModuleLoader = require("@self/createModuleLoader")
local isSandboxed = require("@self/isSandboxed")
local types = require("@self/types")

export type ModuleLoader = types.PublicModuleLoader
export type LastError = types.LastError

return {
	createModuleLoader = createModuleLoader,
	isSandboxed = isSandboxed,
}
