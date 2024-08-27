export type ModuleConsumers = {
	[string]: boolean,
}

-- Each module gets its own global table that it can modify via _G. This makes
-- it easy to clear out a module and the globals it defines without impacting
-- other modules. A module's function environment has all globals merged
-- together on _G
export type ModuleGlobals = {
	[any]: any,
}

return {}
