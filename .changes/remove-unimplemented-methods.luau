return {
	bump = "major",
	category = "Changes",
	kind = "cache",
	flags = { "Breaking" },
	summary = "Remove `isLocked` and `clearModule` from the `ModuleLoader` type, which declared them without an implementation.",
	body = "Calling either one already errored at runtime, so only code that type-checks against them needs a change. Delete those calls, and use `clear` to empty the whole cache.",
}
