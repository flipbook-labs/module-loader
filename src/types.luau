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

--[=[
	What `getLastError` returns about the most recent failed `require`.

	@interface LastError
	@within ModuleLoader
	.err unknown -- The value the module raised, exactly as `require` raised it.
	.traceback string -- The stack where the module raised it, one frame per line.
]=]
export type LastError = {
	err: unknown,
	traceback: string,
}

--[=[
	A loader made by `createModuleLoader`.

	@interface ModuleLoader
	@within ModuleLoader
	.require (moduleScript: ModuleScript) -> ...unknown -- Requires a module, and every module it requires, without Roblox's require cache. Requiring it again returns the same result until `clear` is called. A module's error is raised exactly as the module raised it, without a traceback.
	.cache (moduleScript: ModuleScript, ...unknown) -> () -- Sets the result `require` returns for a module before it loads, so loaded modules share a copy you already have, such as a UI library.
	.clear () -> () -- Empties the loader's cache, so the next `require` runs each module again.
	.getLastError () -> LastError? -- Returns the error from the most recent failed `require` and the stack where the module raised it, or nil after a `require` that succeeds and after `clear`.
	.loadedModuleChanged RBXScriptSignal -- Fires when a module required through this loader has its ancestry or `Source` changed.
]=]
-- `createModuleLoader` returns more than these fields, such as the module
-- registry its specs read. The package exports this narrower type so those
-- stay out of the public API.
export type PublicModuleLoader = {
	require: (moduleScript: ModuleScript) -> ...unknown?,
	cache: (moduleScript: ModuleScript, ...unknown?) -> (),
	clear: () -> (),
	getLastError: () -> LastError?,

	loadedModuleChanged: RBXScriptSignal,
}

export type ModuleLoader = {
	_getModuleRegistry: () -> ModuleRegistry,

	require: (moduleScript: ModuleScript) -> ...unknown?,
	loadModule: (moduleScript: ModuleScript) -> ...unknown?,
	cache: (moduleScript: ModuleScript, ...unknown?) -> (),
	clear: () -> (),
	getLastError: () -> LastError?,

	loadedModuleChanged: RBXScriptSignal,
}

-- A module's code, compiled but not yet run.
export type ModuleChunk = () -> ...unknown

-- A module's code wrapped so the loader can hand it its own `script`,
-- `require`, and `_G`.
export type ModuleFunction = (script: ModuleScript, require: unknown, globals: unknown) -> ...unknown?

-- Roblox signature for `debug.loadmodule`: the module's chunk, or nil and an
-- error message, plus a function that releases the chunk.
export type LoadModule = (moduleScript: ModuleScript) -> (ModuleChunk?, string?, (() -> ())?)

-- Resolves a string require, such as `./Sibling` or `@alias/Module`, relative
-- to the module that called `require`.
export type ResolveModulePath = (relativeTo: Instance, path: string) -> Instance

-- The engine calls a loader makes. Specs replace them to simulate security
-- contexts that Open Cloud Luau Execution can't reproduce.
export type ModuleLoaderDependencies = {
	compile: (source: string, chunkName: string) -> (ModuleChunk?, string?),
	require: (moduleScript: ModuleScript) -> unknown,
	loadmodule: LoadModule?,
	-- When nil, string requires go through ModuleLoader's own path parser.
	resolveModulePath: ResolveModulePath?,
}

return nil
