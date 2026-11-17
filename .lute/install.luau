local fs = require("@std/fs")
local luau = require("@std/luau")
local path = require("@std/path")
local process = require("@std/process")

local project = require("@repo/project")

local LOCKFILE_PATH = "pkg.lock.luau"
local VENDOR_PATH = "LuauPackages"

-- `lute pkg install` puts each dependency in the Loom store, `~/.loom/store`,
-- under a folder whose name includes hashes of its source and rev. Requires
-- resolve only through aliases in `.config.luau`, which can't name a dependency
-- from the lockfile. So after installing, this copies each dependency into
-- `LuauPackages/<name>`, using its name from `pkg.luau`, and `.config.luau`
-- aliases those folders. https://github.com/flipbook-labs/flipbook/issues/689
-- tracks removing this once Lute resolves dependencies by name.

type Lockfile = {
	dependencies: { [string]: string },
	devDependencies: { [string]: string }?,
	packages: { [string]: { installPath: string } },
}

-- The lockfile writes `@pkg/` for the store, and the path of a dependency
-- without a `target` ends in `/.`.
local function getStorePath(lockfile: Lockfile, key: string): path.Path
	local installPath = lockfile.packages[key].installPath
	local relative = installPath:gsub("^@pkg/", ""):gsub("/%.$", "")
	return path.join(process.homedir(), ".loom", "store", relative)
end

local function copyDirectory(src: path.Path, dest: path.Path)
	fs.createDirectory(dest, { makeParents = true })
	for _, entry in fs.listDirectory(src) do
		local from = path.join(src, entry.name)
		local to = path.join(dest, entry.name)
		if entry.type == "dir" then
			copyDirectory(from, to)
		else
			fs.copy(from, to)
		end
	end
end

-- The Wally step below requires flipbook-batteries, so the Loom dependencies
-- are installed and vendored first.
do
	local result = process.run({ "lute", "pkg", "install" }, { stdio = "inherit" })
	assert(result.ok, "lute pkg install failed")

	local lockfile: Lockfile = luau.loadModule(LOCKFILE_PATH)

	-- Clearing the folder first drops dependencies that `pkg.luau` no longer lists.
	if fs.exists(VENDOR_PATH) then
		fs.removeDirectory(VENDOR_PATH, { recursive = true })
	end

	for _, dependencies in { lockfile.dependencies, lockfile.devDependencies or {} } do
		for name, key in dependencies do
			copyDirectory(getStorePath(lockfile, key), path.join(VENDOR_PATH, name))
		end
	end

	print(`Vendored dependencies into {VENDOR_PATH}`)
end

do
	local FlipbookBatteries = require("@flipbook-batteries")

	local run = FlipbookBatteries.run

	local function installWallyPackages()
		run("wally", { "install" })
		run("rojo", { "sourcemap", project.ROJO_BUILD_PROJECT, "-o", "sourcemap.json" })
		run("wally-package-types", { "--sourcemap", "sourcemap.json", project.PACKAGES_PATH })
	end

	run("lute", { "setup" })

	installWallyPackages()
end
