return {
	bump = "minor",
	category = "Changes",
	kind = "requiring",
	summary = "`require` raises a LoadError that keeps the error's message apart from its traceback; check one with `ModuleLoader.isLoadError`.",
	body = "`tostring` on a LoadError gives the same text `require` raised before, so code that calls string methods on the error needs `tostring(err)` first. A table that a module raises now reaches the caller as it was raised.",
}
