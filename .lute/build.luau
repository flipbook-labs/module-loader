local FlipbookBatteries = require("@lpm/flipbook-batteries@v0.13.1")
local cli = require("@scripts/batteries/cli")
local fs = require("@std/fs")
local path = require("@std/path")

local project = require("@repo/project")

local run = FlipbookBatteries.run
local watch = FlipbookBatteries.watch
local find = FlipbookBatteries.find

local args = cli.parser()

args:add("channel", "option", {
	help = "Channel to build for",
	aliases = { "c" },
	default = "prod",
})
args:add("watch", "flag", {
	help = "Watch for changes and recompile automatically",
	aliases = { "w" },
})
args:add("output", "option", {
	help = "Choose where to output to. This should be the full name of the file, including the .rbxm extension",
	aliases = { "o" },
})

args:parse({ ... })

local channel = args:get("channel")
assert(channel == "dev" or channel == "prod", `bad value for channel (must be one of "dev" or "prod", got "{channel}")`)

local output = args:get("output")
if output then
	assert(output ~= "", `bad value for --output (pathto an rbxm file expected, got {output})`)
end

local function build()
	fs.removeDirectory(project.BUILD_PATH, {
		recursive = true,
	})
	fs.createDirectory(project.BUILD_PATH, {
		makeParents = true,
	})

	run("rojo", {
		"sourcemap",
		project.ROJO_BUILD_PROJECT,
		"-o",
		project.DARKLUA_SOURCEMAP_PATH,
	})

	run("darklua", {
		"process",
		project.SOURCE_PATH,
		project.BUILD_PATH,
	})

	-- `src/.config.luau` gives Lute consumers the package's own aliases. The
	-- Roblox build has already converted those requires, and Rojo would turn the
	-- file into a ModuleScript named `.config`, so it stays out of `dist/`.
	fs.remove(path.join(project.BUILD_PATH, ".config.luau"))

	if channel == "prod" then
		for _, specFile in find(project.BUILD_PATH, ".*%.spec%.luau") do
			fs.remove(specFile)
		end
	end

	if output then
		run("rojo", { "build", "-o", output })
	end
end

build()

if args:has("watch") then
	watch({
		roots = {
			project.SOURCE_PATH,
		},
		excludedFilePatterns = {
			".*Packages",
			"dist",
		},
		onChanged = build,
	})
end
