local createModuleLoader = require("@self/createModuleLoader")
local isSandboxed = require("@self/isSandboxed")
local types = require("@self/types")

export type ModuleLoader = types.PublicModuleLoader

return {
	createModuleLoader = createModuleLoader :: () -> ModuleLoader,
	isSandboxed = isSandboxed,
}
