return {
	package = {
		name = "ModuleLoader",
		version = "0.12.1",
		-- `src/.config.luau` is hidden, so it has to be named to ship.
		files = { "/src/**", "/src/.config.luau", "!/src/**/*.spec.luau", "!/src/jest.config.luau", "/README.md", "/LICENSE" },
		dependencies = {
			["flipbook-batteries"] = {
				rev = "v0.13.1",
				sourceKind = "github",
				source = "https://github.com/flipbook-labs/flipbook-batteries",
			},
		},
		dev_dependencies = {
			["code-quality"] = {
				rev = "v0.7.0",
				sourceKind = "github",
				source = "https://github.com/flipbook-labs/code-quality",
			},
			["agent-skills"] = {
				rev = "v0.7.0",
				sourceKind = "github",
				source = "https://github.com/flipbook-labs/agent-skills",
			},
		},
	},
}
