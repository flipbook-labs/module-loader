local LoadError = require("@self/LoadError")
local ModuleLoader = require("@self/ModuleLoader")

export type ModuleLoader = ModuleLoader.ModuleLoaderClass
export type Class = ModuleLoader.ModuleLoaderClass
export type LoadError = LoadError.LoadError

return ModuleLoader
