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
-- can't name a dependency from the lockfile. So after installing, this copies
-- each dependency's store path from the lockfile into its alias.
-- https://github.com/flipbook-labs/flipbook/issues/689 tracks removing this.
--
-- The hashes depend only on the source and rev, so the paths are the same on
-- every machine, and `.config.luau` commits them. A consumer that installs this
-- package from the store resolves its aliases through those committed paths,
-- without running this script.
--
-- Keys are aliases in `.config.luau`, and values are dependency names in
-- `pkg.luau`. `agent-skills` points agents at the shared skills library, and
-- `lute run lint` reads the CodeQuality rules through `code-quality`.
local DEPENDENCY_ALIASES: { [string]: string } = {
	["flipbook-batteries"] = "FlipbookBatteries",
	["agent-skills"] = "AgentSkills",
	["code-quality"] = "CodeQuality",
}

type Lockfile = {
	dependencies: { [string]: string },
	devDependencies: { [string]: string }?,
	packages: { [string]: { installPath: string } },
}

-- The lockfile writes `@pkg/` for the store, and the path of a dependency
-- without a target ends in `/.`.
local function getStorePath(lockfile: Lockfile, name: string): string
	local key = lockfile.dependencies[name] or (lockfile.devDependencies and lockfile.devDependencies[name])
	assert(key, `{name} is not a dependency in {LOCKFILE_PATH}`)

	local installPath = lockfile.packages[key].installPath
	local storePath = installPath:gsub("^@pkg/", "~/.loom/store/"):gsub("/%.$", "")
	return storePath
end

local result = process.run({ "lute", "pkg", "install" }, { stdio = "inherit" })
assert(result.ok, "lute pkg install failed")

local lockfile: Lockfile = luau.loadModule(LOCKFILE_PATH)
local config = fs.readFileToString(CONFIG_PATH)

for alias, name in DEPENDENCY_ALIASES do
	local storePath = getStorePath(lockfile, name)

	-- An alias that isn't a plain identifier, like `agent-skills`, is written
	-- as a quoted key, `["agent-skills"]`. Each alias sits on its own line, so
	-- the match starts at a line break.
	local key = if alias:match("^[%a_][%w_]*$") then alias else `["{alias}"]`
	local keyPattern = key:gsub("%p", "%%%0")
	local updated, count = config:gsub(`(\n%s*{keyPattern}%s*=%s*")[^"]*(")`, `%1{storePath}%2`)
	assert(count == 1, `Expected one "{alias}" alias in {CONFIG_PATH}, found {count}`)
	config = updated
end

fs.writeStringToFile(CONFIG_PATH, config)
print(`Wrote dependency aliases to {CONFIG_PATH}`)

do
	local FlipbookBatteries = require("@flipbook-batteries")

	local run = FlipbookBatteries.run

	local function installWallyPackages()
		run("wally", { "install" })
		run("rojo", {
			"sourcemap",
			project.ROJO_BUILD_PROJECT,
			"-o",
			"sourcemap.json",
		})
		run("wally-package-types", { "--sourcemap", "sourcemap.json", project.PACKAGES_PATH })
	end

	run("lute", { "setup" })

	installWallyPackages()
end
