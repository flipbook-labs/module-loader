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

return nil
