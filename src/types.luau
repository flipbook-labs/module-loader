export type LoadedModuleExports = unknown

export type LoadedModule = {
	instance: ModuleScript,
	isLoaded: boolean,
	exports: LoadedModuleExports,
	dependencies: { [ModuleScript]: boolean },
	consumers: { [ModuleScript]: boolean },
}

export type ModuleRegistry = {
	add: (moduleScript: ModuleScript, loadedModule: LoadedModule) -> (),
	remove: (moduleScript: ModuleScript) -> (),
	reset: () -> (),
	getAllModules: () -> { ModuleScript },
	getByInstance: (moduleScript: ModuleScript) -> LoadedModule?,
	getByFullName: (fullName: string) -> LoadedModule?,
}

return nil
