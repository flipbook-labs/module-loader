--[[
	Builds ModuleLoader and copies the build over the ModuleLoader that a
	Storyteller or Flipbook checkout installs, so that checkout can try
	unreleased changes. Wally can't install path or git dependencies, so this
	stands in for one.

	Flipbook gets ModuleLoader only through Storyteller. Passing both
	checkouts also runs that Storyteller checkout's `try-in-flipbook`, so
	Flipbook ends up with a Storyteller build from it as well. The next
	`lute run install` in a checkout puts the released packages back.
]]

local FlipbookBatteries = require("@lpm/flipbook-batteries@v0.14.0")
local path = require("@std/path")

local cli = require("@scripts/batteries/cli")
local project = require("@repo/project")

local overlayWallyPackage = FlipbookBatteries.overlayWallyPackage
local run = FlipbookBatteries.run

local args = cli.parser()
args:add("storyteller", "option", {
	help = "path to a Storyteller checkout to receive the build",
})
args:add("flipbook", "option", {
	help = "path to a Flipbook checkout to receive the build",
})
args:parse({ ... })

local storytellerRoot = args:get("storyteller")
local flipbookRoot = args:get("flipbook")

local targets: { string } = {}
if storytellerRoot then
	table.insert(targets, storytellerRoot)
end
if flipbookRoot then
	table.insert(targets, flipbookRoot)
end

if #targets == 0 then
	error("pass at least one checkout with --storyteller <path> or --flipbook <path>")
end

run("lute", { "run", "build" })

for _, target in targets do
	overlayWallyPackage({
		package = "flipbook-labs/module-loader",
		build = path.resolve(project.BUILD_PATH),
		manifest = path.resolve("wally.toml"),
		target = target,
	})
end

if storytellerRoot and flipbookRoot then
	run("lute", {
		"run",
		"try-in-flipbook",
		"--flipbook",
		path.resolve(flipbookRoot),
	}, {
		cwd = storytellerRoot,
	})
end
