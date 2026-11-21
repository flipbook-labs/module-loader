-- The package's own aliases. This file ships with the package (see `files` in
-- `pkg.luau`), and the repo-root `.config.luau` doesn't. Dependency aliases,
-- such as `@lpm`, aren't defined here, so a consumer's config supplies them.
return {
	luau = {
		aliases = {
			root = "./",
		},
	},
}
