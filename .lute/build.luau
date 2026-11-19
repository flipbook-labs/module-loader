local FlipbookBatteries = require("@flipbook-batteries")
local cli = require("@scripts/batteries/cli")
local fs = require("@std/fs")
local json = require("@std/json")
local path = require("@std/path")

local project = require("@repo/project")
local rewriteLuau = require("@scripts/lib/rewriteLuau")

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

	-- The rewriter turns string requires into `require(script...)` paths. It
	-- reads which instance each file becomes from a sourcemap of
	-- `build.project.json`, which mounts `src/` as `ModuleLoader` inside
	-- `Packages`. That's where `tests.project.json` mounts `dist/`, and `dist/`
	-- copies `src/` file for file, so the same paths hold there.
	run("rojo", {
		"sourcemap",
		project.ROJO_BUILD_PROJECT,
		"-o",
		project.BUILD_SOURCEMAP_PATH,
	})

	local sourcemap: unknown = json.deserialize(fs.readFileToString(project.BUILD_SOURCEMAP_PATH))
	local rewriter = rewriteLuau.create({
		repoPath = path.format(path.resolve(".")),
		sourcemap = sourcemap :: rewriteLuau.SourcemapNode,
		globalNames = {},
		globalValues = {},
	})
	rewriteLuau.rewriteFolder(rewriter, path.resolve(project.SOURCE_PATH), path.resolve(project.BUILD_PATH))

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
