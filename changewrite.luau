return {
	categories = { "Features", "Changes", "Fixes", "Dependencies", "Internal" },
	collapsed = { "Dependencies", "Internal" },
	version = {
		current = "1.0.1",
		mirror = {
			{ file = "wally.toml" },
			{ file = "pkg.luau" },
			{ file = "README.md", pattern = "flipbook%-labs/module%-loader@([%d%.]+)" },
			{ file = "README.md", pattern = 'rev = "v([%d%.]+)"' },
		},
	},
	kind = {
		release = { text = "Release", color = "#94606f" },
		build = { text = "Build", color = "#5a7396" },
		cache = { text = "Cache", color = "#0e7490" },
		ci = { text = "CI", color = "#75659a" },
		contributing = { text = "Contributing", color = "#5f7f55" },
		docs = { text = "Docs", color = "#8a5a2b" },
		events = { text = "Events", color = "#bf3989" },
		packages = { text = "Packages", color = "#7a7444" },
		requiring = { text = "Requiring", color = "#5b5bd6" },
		sandbox = { text = "Sandbox", color = "#1a7f37" },
		tooling = { text = "Tooling", color = "#4e8079" },
	},
}
