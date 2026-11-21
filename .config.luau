return {
	luau = {
		languagemode = "strict",
		aliases = {
			lint = "~/.lute/typedefs/1.0.1/lint",
			lute = "~/.lute/typedefs/1.0.1/lute",
			std = "~/.lute/typedefs/1.0.1/std",
			lpm = "./.lpm",
			pkg = "./Packages",
			root = "./src",
			scripts = "./.lute",
			repo = ".",
		},
	},
	lute = {
		lint = {
			ruleconfigs = {
				-- ModuleLoader keeps its sandbox flag in `_G`, and the specs
				-- and test runner set `_G` fields on purpose. `selene.toml`
				-- allows `global_usage` everywhere, and this matches it.
				global_usage = { off = true },
			},
		},
	},
}
