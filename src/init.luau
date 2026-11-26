local ModuleLoadError = require("@self/ModuleLoadError")
local ModuleLoader = require("@self/ModuleLoader")

export type ModuleLoader = ModuleLoader.ModuleLoaderClass
export type Class = ModuleLoader.ModuleLoaderClass
export type ModuleLoadError = ModuleLoadError.ModuleLoadError

return ModuleLoader
