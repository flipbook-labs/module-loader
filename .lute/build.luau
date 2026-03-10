local FlipbookBatteries = require("@luaupkg/flipbook-batteries")
local cli = require("@scripts/batteries/cli")
local fs = require("@std/fs")

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

args:parse({ ... })

local channel = args:get("channel")
assert(channel == "dev" or channel == "prod", `bad value for channel (must be one of "dev" or "prod", got "{channel}")`)

local function build()
	fs.removedirectory(project.BUILD_PATH, {
		recursive = true,
	})
	fs.createdirectory(project.BUILD_PATH, {
		makeparents = true,
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

	if channel == "prod" then
		for _, specFile in find(project.BUILD_PATH, ".*%.spec%.luau") do
			fs.remove(specFile)
		end
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
