local CodeQuality = require("@code-quality")
local FlipbookBatteries = require("@flipbook-batteries")
local cli = require("@scripts/batteries/cli")
local fs = require("@std/fs")
local path = require("@std/path")

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

-- The build turns a copy of `src/` in `dist/` into code Roblox can run, using
-- CodeQuality's code mods. `lute transform` runs one mod over every file and
-- rewrites them in place. `convertRequire` turns string requires into
-- `require(script...)` paths. The rest fold constant expressions and remove the
-- code that can never run. They go in the order CodeQuality's README lists,
-- since a later mod cleans up what an earlier one leaves behind, such as the
-- empty `do ... end` blocks `removeEmptyDo` removes.
local function transform(mod: string, ...: string)
	run("lute", {
		"transform",
		path.format(path.join(CodeQuality.MODS_PATH, `{mod}.luau`)),
		project.BUILD_PATH,
		"--",
		...,
	})
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

	-- `convertRequire` reads which instance each file becomes from a sourcemap
	-- of `build.project.json`, which mounts `src/` as `ModuleLoader` inside
	-- `Packages`. `tests.project.json` mounts `dist/` in the same place,
	-- through `default.project.json`. The sourcemap names files in `src/`, so
	-- `--sourceFolder` and `--buildFolder` tell the mod to look up each file in
	-- `dist/` by its path in `src/`.
	run("rojo", {
		"sourcemap",
		project.ROJO_BUILD_PROJECT,
		"-o",
		project.BUILD_SOURCEMAP_PATH,
	})

	transform(
		"convertRequire",
		"--sourcemap",
		project.BUILD_SOURCEMAP_PATH,
		"--sourceFolder",
		project.SOURCE_PATH,
		"--buildFolder",
		project.BUILD_PATH
	)
	transform("computeExpression")
	transform("removeUnusedIfBranch")
	transform("removeUnusedWhile")
	transform("filterAfterEarlyReturn")
	transform("removeNilDeclaration")
	transform("removeEmptyDo")

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
