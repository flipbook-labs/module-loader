return {
	luau = {
		languagemode = "strict",
		aliases = {
			lint = "~/.lute/typedefs/1.0.1/lint",
			lute = "~/.lute/typedefs/1.0.1/lute",
			std = "~/.lute/typedefs/1.0.1/std",
			pkg = "./Packages",
			root = "./src",
			scripts = "./.lute",
			repo = ".",

			-- The store folder's name hashes the dependency's source and rev, so
			-- this path is the same on every machine. `lute run install`
			-- rewrites it from `pkg.lock.luau` when the rev changes.
			["flipbook-batteries"] = "~/.loom/store/flipbook-batteries--github-cd561061b96224c3881d0f76944a9bb8bad2d09ff72e9e09eb3cfaa2e62b6613@2f0b52aa834b5bccd5b10d223b712227121916715a67505b557393845d5af93e",
		},
	},
}
