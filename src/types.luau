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

-- `unknown` here fails the type checks in createModuleLoader, which passes module functions around.
-- lute-lint-ignore(no_any)
export type ModuleFunction = (...any) -> ...unknown?

-- Roblox signature for `debug.loadmodule`: the module's chunk, or nil and an
-- error message, plus a function that releases the chunk.
export type LoadModule = (moduleScript: ModuleScript) -> ((() -> ...unknown)?, string?, (() -> ())?)

-- Resolves a string require, such as `./Sibling` or `@alias/Module`, relative
-- to the module that called `require`.
export type ResolveModulePath = (relativeTo: Instance, path: string) -> Instance

-- The engine calls a loader makes. Specs replace them to simulate security
-- contexts that Open Cloud Luau Execution can't reproduce.
export type ModuleLoaderDependencies = {
	compile: (source: string, chunkName: string) -> (ModuleFunction?, string?),
	require: (moduleScript: ModuleScript) -> unknown,
	loadmodule: LoadModule?,
	-- When nil, string requires go through ModuleLoader's own path parser.
	resolveModulePath: ResolveModulePath?,
}

return nil
