--[[
	This script is solely for taking our dev build of ModuleLoader and overlaying
	it on Flipbook's install. This is only needed because Wally doesn't support
	path/git dependencies, so we have to make our own shim.
]]

local FlipbookBatteries = require("@luaupkg/flipbook-batteries")
local fs = require("@std/fs")
local path = require("@std/path")

local run = FlipbookBatteries.run
local copyInto = FlipbookBatteries.copyInto
local find = FlipbookBatteries.find

local BUNDLE_DIR_NAME = "dist"

local function resolveScriptPath(scriptPath: string)
	--[[
        Lute's script paths are inconsistent depending on how you invoke them.
        With `lute run <scriptName>`, scriptPath is exactly `scriptName`. As
        such we need to manually resolve the path to the script.

        Track progress here: https://github.com/luau-lang/lute/issues/852
    ]]
	if scriptPath == path.basename(scriptPath) then
		return path.resolve(`.lute/{scriptPath}.luau`)
	end

	return scriptPath
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
		`could not find Flipbook at {flipbookRoot}. Make sure your checkout is parented to the same directory as ModuleLoader`
	)
end

local flipbookPackageIndex = path.join(flipbookRoot, "Packages/_Index")
local moduleLoaderInstallation = find(flipbookPackageIndex, "^module%-loader$")[1]

if not moduleLoaderInstallation or not fs.exists(moduleLoaderInstallation) then
	error("could not find an installation of ModuleLoader in Flipbook's package index")
end

local dest = path.join(moduleLoaderInstallation, BUNDLE_DIR_NAME)

fs.removedirectory(dest, {
	recursive = true,
})

run("lute", { "run", "build" })
copyInto(src, dest)

print(`successfully installed to {dest}`)
