return {
	bump = "major",
	category = "Changes",
	kind = "requiring",
	flags = { "Breaking" },
	summary = "`require` raises a ModuleLoadError that keeps the error's message apart from its traceback; check one with `isModuleLoadError`.",
	body = "`tostring` on a ModuleLoadError gives the same text `require` raised before, so code that calls string methods on the error needs `tostring(err)` first. A table that a module raises now reaches the caller as it was raised.",
}
