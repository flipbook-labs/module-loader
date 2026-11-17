export type Packed<T> = { [number]: T, n: number }

export type LoadedModule = {
	instance: ModuleScript,
	isLoaded: boolean,
	exports: Packed<unknown>?,
}

export type ModuleRegistry = {
	add: (moduleScript: ModuleScript, loadedModule: LoadedModule) -> (),
	remove: (moduleScript: ModuleScript) -> (),
	reset: () -> (),
	getAllModules: () -> { ModuleScript },
	getByInstance: (moduleScript: ModuleScript) -> LoadedModule?,
	getByFullName: (fullName: string) -> LoadedModule?,
}

export type ModuleLoader = {
	_getModuleRegistry: () -> ModuleRegistry,

	require: (moduleScript: ModuleScript) -> ...unknown?,
	loadModule: (moduleScript: ModuleScript) -> ...unknown?,
	cache: (moduleScript: ModuleScript, ...unknown?) -> (),
	clear: () -> (),

	loadedModuleChanged: RBXScriptSignal,
}

export type ModuleFunction = (...any) -> ...unknown?

-- Roblox signature for `debug.loadmodule`: the module's chunk, or nil and an
-- error message, plus a function that releases the chunk.
export type LoadModule = (moduleScript: ModuleScript) -> ((() -> ...unknown)?, string?, (() -> ())?)

-- The engine calls a loader makes. Specs replace them to simulate security
-- contexts that Open Cloud Luau Execution can't reproduce.
export type ModuleLoaderDependencies = {
	compile: (source: string, chunkName: string) -> (ModuleFunction?, string?),
	require: (moduleScript: ModuleScript) -> ...any,
	loadmodule: LoadModule?,
}

return nil
