--[[
	This script is solely for taking our dev build of Storyteller and overlaying
	it on Flipbook's install. This is only needed because Wally doesn't support
	path/git dependencies, so we have to make our own shim.
]]

local FlipbookBatteries = require("@luaupkg/flipbook-batteries")
local fs = require("@std/fs")
local path = require("@std/path")

local run = FlipbookBatteries.run
local copyInto = FlipbookBatteries.copyInto
local find = FlipbookBatteries.find

local WALLY_PACKAGE_NAME_PATTERN = "^module%-loader$"
local BUNDLE_DIR_NAME = "dist"

local function resolveScriptPath(scriptPath: string): path.path
	--[[
        Lute's script paths are inconsistent depending on how you invoke them.
        With `lute run <scriptName>`, scriptPath is exactly `scriptName`. As
        such we need to manually resolve the path to the script.

        Track progress here: https://github.com/luau-lang/lute/issues/852
    ]]
	if scriptPath == path.basename(scriptPath) then
		return path.resolve(`.lute/{scriptPath}.luau`)
	end

	return path.parse(scriptPath)
end

local args = { ... }

local scriptPath = resolveScriptPath(args[1])
local repoRoot = path.dirname(path.dirname(scriptPath))
local src = path.resolve(path.join("./", BUNDLE_DIR_NAME))
local flipbookRoot = path.resolve(path.join(repoRoot, "../flipbook"))

if fs.exists(flipbookRoot) then
	print(`using Flipbook at {flipbookRoot}`)
else
	error(
		`could not find Flipbook at {flipbookRoot}. Make sure your checkout is parented to the same directory as this repo`
	)
end

local flipbookPackageIndex = path.join(flipbookRoot, "Packages/_Index")
local packageInstallation = find(flipbookPackageIndex, WALLY_PACKAGE_NAME_PATTERN)[1]

if not packageInstallation or not fs.exists(packageInstallation) then
	error("could not find an installation of this package in Flipbook's package index")
end

local dest = path.join(packageInstallation, BUNDLE_DIR_NAME)

fs.removedirectory(dest, {
	recursive = true,
})

run("lute", { "run", "build" })
copyInto(src, dest)

print(`successfully installed to {dest}`)
