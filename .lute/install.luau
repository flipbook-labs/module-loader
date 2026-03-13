local fs = require("@std/fs")
local path = require("@std/path")
local process = require("@std/process")

local loomConfig = require("@repo/loom.config")
local project = require("@repo/project")

local function move(src: path.pathlike, dest: path.pathlike)
	local res = process.run({ "mv", tostring(src), tostring(dest) }, {
		stdio = "inherit",
	})
	assert(res.ok, res.stderr)
end

-- Install Loom dependencies first since the rest of the script depends on them
do
	local res = process.run({ "lute", "pkg", "install" }, {
		stdio = "inherit",
	})
	assert(res.ok, res.stderr)

	fs.removedirectory(project.LUAU_PACKAGES_PATH, {
		recursive = true,
	})
	fs.createdirectory(project.LUAU_PACKAGES_PATH)

	-- Since Wally and Loom both write to the Packages dir, we disambiguate our
	-- packages by moving all the Loom dependencies into LuauPackages
	for dependencyName in loomConfig.package.dependencies :: { [string]: unknown } do
		move(path.join(project.PACKAGES_PATH, dependencyName), path.join(project.LUAU_PACKAGES_PATH, dependencyName))
	end
end

do
	local FlipbookBatteries = require("@luaupkg/flipbook-batteries")

	local run = FlipbookBatteries.run

	local function installWallyPackages()
		run("wally", { "install" })
		run("rojo", { "sourcemap", project.ROJO_BUILD_PROJECT, "-o", "sourcemap.json" })
		run("wally-package-types", { "--sourcemap", "sourcemap.json", project.PACKAGES_PATH })
	end

	run("lute", { "setup" })

	installWallyPackages()
end
