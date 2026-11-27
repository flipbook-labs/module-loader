return {
	bump = "major",
	category = "Changes",
	kind = "requiring",
	flags = { "Breaking" },
	summary = "Replace the `ModuleLoader` class with functions: `createModuleLoader` makes a loader whose functions are called with `.`.",
	body = "Call `ModuleLoader.createModuleLoader()` where you called `ModuleLoader.new()`, then `loader.require(module)`, `loader.cache(module, value)`, and `loader.clear()` in place of the `:` methods. `isSandboxed` and `isModuleLoadError` stay on the package. The `ModuleLoader.Class` type is gone, so use `ModuleLoader.ModuleLoader` for a loader. A loader's `require` returns `unknown` instead of `any`, so typed callers narrow or cast what a module returns.",
}
