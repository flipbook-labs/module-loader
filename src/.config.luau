-- The package's own aliases. This file ships with the package (see `files` in
-- `pkg.luau`), unlike the repo-root `.config.luau`, whose generated store
-- aliases would point a vendored copy back at the Loom store. Dependency
-- aliases aren't defined here, so a consumer's config supplies them.
return {
	luau = {
		aliases = {
			root = "./",
		},
	},
}
