local CodeQuality = require("@lpm/code-quality@v0.8.0")
local FlipbookBatteries = require("@lpm/flipbook-batteries@v0.14.0")
local cli = require("@scripts/batteries/cli")
local fs = require("@std/fs")

local project = require("@repo/project")

local copyInto = FlipbookBatteries.copyInto
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
	copyInto(project.SOURCE_PATH, project.BUILD_PATH)

	if channel == "prod" then
		for _, specFile in find(project.BUILD_PATH, ".*%.spec%.luau") do
			fs.remove(specFile)
		end
	end

	--[[
		CodeQuality's build, below, turns the copy in `dist/` into code Roblox
		can run. To turn a string require into a `require(script...)` path, it
		has to know which Roblox instance each file becomes. It reads that from
		this Rojo sourcemap of `build.project.json`, which mounts `src/` as
		`ModuleLoader` inside a `Packages` folder. `tests.project.json` mounts
		`dist/` the same way, as `ModuleLoader` inside its own `Packages`
		folder, so the paths work there too. The sourcemap names files in
		`src/`, so `sourceFolder` and `buildFolder` tell the build to look up
		each file in `dist/` by its path in `src/`.
	]]
	run("rojo", {
		"sourcemap",
		project.ROJO_BUILD_PROJECT,
		"-o",
		project.BUILD_SOURCEMAP_PATH,
	})

	CodeQuality.build({
		sourceFolder = project.SOURCE_PATH,
		buildFolder = project.BUILD_PATH,
		sourcemap = project.BUILD_SOURCEMAP_PATH,
	})

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
