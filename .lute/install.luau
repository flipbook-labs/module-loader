local fs = require("@std/fs")
local luau = require("@std/luau")
local process = require("@std/process")

local project = require("@repo/project")

local CONFIG_PATH = ".config.luau"
local LOCKFILE_PATH = "pkg.lock.luau"

-- `lute pkg install` puts each dependency in the Loom store, `~/.loom/store`,
-- under a folder whose name includes hashes of its source and rev. The
-- lockfile records where each one landed, but `lute check` and editors read
-- aliases only from `.config.luau`. So after installing, this writes each
-- recorded path into that dependency's alias in `.config.luau`. Keys are
-- aliases in `.config.luau`, and values are dependency names in `pkg.luau`.
local DEPENDENCY_ALIASES: { [string]: string } = {
	["flipbook-batteries"] = "flipbook-batteries",
}

type Lockfile = {
	dependencies: { [string]: string },
	devDependencies: { [string]: string }?,
	packages: { [string]: { installPath: string } },
}

local function getStorePath(lockfile: Lockfile, name: string): string
	local key = lockfile.dependencies[name] or (lockfile.devDependencies and lockfile.devDependencies[name])
	assert(key, `{name} is not a dependency in {LOCKFILE_PATH}`)

	-- The lockfile writes `@pkg/` for the store, and the path of a dependency
	-- without a target ends in `/.`.
	local installPath = lockfile.packages[key].installPath
	return (installPath:gsub("^@pkg/", "~/.loom/store/"):gsub("/%.$", ""))
end

local function escapePattern(text: string): string
	return (text:gsub("%p", "%%%0"))
end

-- The rest of this script requires flipbook-batteries, so the Loom
-- dependencies are installed and their aliases written first.
do
	local res = process.run({ "lute", "pkg", "install" }, {
		stdio = "inherit",
	})
	assert(res.ok, res.stderr)

	local lockfile: Lockfile = luau.loadModule(LOCKFILE_PATH)
	local config = fs.readFileToString(CONFIG_PATH)

	for alias, name in DEPENDENCY_ALIASES do
		local storePath = getStorePath(lockfile, name)
		local key = escapePattern(`["{alias}"]`)
		local updated, count = config:gsub(`({key}%s*=%s*")[^"]*(")`, `%1{storePath}%2`)
		assert(count == 1, `Expected one "{alias}" alias in {CONFIG_PATH}, found {count}`)
		config = updated
	end

	fs.writeStringToFile(CONFIG_PATH, config)
	print(`wrote dependency aliases to {CONFIG_PATH}`)
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
