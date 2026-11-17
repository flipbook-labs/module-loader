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

			-- `lute run install` copies these from the Loom store.
			-- https://github.com/flipbook-labs/flipbook/issues/689 tracks removing this vendoring.
			["flipbook-batteries"] = "./LuauPackages/FlipbookBatteries",
		},
	},
}
