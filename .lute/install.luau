local fs = require("@std/fs")
local luau = require("@std/luau")
local process = require("@std/process")

local project = require("@repo/project")

local CONFIG_PATH = ".config.luau"
local LOCKFILE_PATH = "pkg.lock.luau"

-- `lute pkg install` puts each dependency in the Loom store, `~/.loom/store`,
-- under a folder whose name includes hashes of its source and rev. A dependency
-- with a `target` in `pkg.luau` installs only that subfolder, like Lute's
-- `batteries`. Requires resolve only through aliases in `.config.luau`, which
-- can't name a dependency from the lockfile. So after installing, this writes
-- an alias for each dependency, named after its key in `pkg.luau`, pointing at
-- the store path the lockfile records for it.
-- https://github.com/flipbook-labs/flipbook/issues/689 tracks removing this.
--
-- The hashes depend only on the source and rev, so the paths are the same on
-- every machine, and `.config.luau` commits them. A consumer that installs this
-- package from the store resolves its aliases through those committed paths,
-- without running this script.
--
-- The aliases go between two marker comments in `.config.luau`. The first is
-- the line that links the issue above, and the second is `END_MARKER`. Every
-- line between them is replaced on each run, so aliases for removed
-- dependencies disappear too.
local END_MARKER = "-- End of aliases written by `lute run install`."

type Lockfile = {
	dependencies: { [string]: string },
	devDependencies: { [string]: string }?,
	packages: { [string]: { installPath: string, sourceKind: string } },
}

-- The lockfile writes `@pkg/` for the store, and the path of a dependency
-- without a target ends in `/.`.
local function getStorePath(installPath: string): string
	local storePath = installPath:gsub("^@pkg/", "~/.loom/store/"):gsub("/%.$", "")
	return storePath
end

-- Keys are lowercase kebab-case, so each one is already a valid alias name. A
-- key with a `-` has to be written as a quoted key.
local function formatAlias(name: string, storePath: string): string
	assert(name:match("^[a-z][a-z0-9-]*$"), `Dependency key "{name}" in pkg.luau must be lowercase kebab-case`)
	local key = if name:find("-") then `["{name}"]` else name
	return `{key} = "{storePath}",`
end

local function getAliasLines(lockfile: Lockfile): { string }
	local storePaths: { [string]: string } = {}
	for _, section in { lockfile.dependencies, lockfile.devDependencies or {} } do
		for name, key in section do
			local package = lockfile.packages[key]
			-- Path dependencies, such as workspace members, already live in the
			-- repository, so they don't need a store alias.
			if package.sourceKind ~= "path" then
				storePaths[name] = getStorePath(package.installPath)
			end
		end
	end

	local names: { string } = {}
	for name in storePaths do
		table.insert(names, name)
	end
	table.sort(names)

	local lines: { string } = {}
	for _, name in names do
		table.insert(lines, formatAlias(name, storePaths[name]))
	end
	return lines
end

local function writeAliases(config: string, aliasLines: { string }): string
	local lines = config:split("\n")
	local startIndex: number? = nil
	local endIndex: number? = nil
	for index, line in lines do
		if line:find("flipbook/issues/689", 1, true) then
			startIndex = index
		elseif line:find(END_MARKER, 1, true) then
			endIndex = index
		end
	end
	local missingMarkers = `{CONFIG_PATH} is missing the alias marker comments`
	local first = assert(startIndex, missingMarkers)
	local last = assert(endIndex, missingMarkers)
	assert(first < last, missingMarkers)

	local indent = lines[first]:match("^%s*") or ""
	local result = table.move(lines, 1, first, 1, {})
	for _, aliasLine in aliasLines do
		table.insert(result, indent .. aliasLine)
	end
	table.move(lines, last, #lines, #result + 1, result)
	return table.concat(result, "\n")
end

local result = process.run({ "lute", "pkg", "install" }, { stdio = "inherit" })
assert(result.ok, "lute pkg install failed")

local lockfile: Lockfile = luau.loadModule(LOCKFILE_PATH)
local config = fs.readFileToString(CONFIG_PATH)
fs.writeStringToFile(CONFIG_PATH, writeAliases(config, getAliasLines(lockfile)))
print(`Wrote dependency aliases to {CONFIG_PATH}`)

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
