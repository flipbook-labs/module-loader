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

			-- `lute run install` writes these paths from `pkg.lock.luau`.
			-- https://github.com/flipbook-labs/flipbook/issues/689 tracks removing this injection.
			["flipbook-batteries"] = "~/.loom/store/flipbook-batteries--github-cd561061b96224c3881d0f76944a9bb8bad2d09ff72e9e09eb3cfaa2e62b6613@2f0b52aa834b5bccd5b10d223b712227121916715a67505b557393845d5af93e",
			["agent-skills"] = "~/.loom/store/agent-skills--github-9a5fa281b004edd0a2d24adfca334a5b9f2dc7230401fbbbd8816c81f971a3ed@50ab7418ec44018e5cfb2826c68fe26616f4ae4399ad5da286264e4e826b123b",
		},
	},
}
