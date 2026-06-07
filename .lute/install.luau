local process = require("@std/process")

local project = require("@repo/project")

-- Install packages managed by Lute first since the rest of the script depends
-- on them.
do
	local res = process.run({ "lute", "pkg", "install" }, {
		stdio = "inherit",
	})
	assert(res.ok, res.stderr)
end

do
	local FlipbookBatteries = require("@luaupkg/flipbook-batteries@v0.10.1")

	local run = FlipbookBatteries.run

	local function installWallyPackages()
		run("wally", { "install" })
		run("rojo", { "sourcemap", project.ROJO_BUILD_PROJECT, "-o", "sourcemap.json" })
		run("wally-package-types", { "--sourcemap", "sourcemap.json", project.PACKAGES_PATH })
	end

	run("lute", { "setup" })

	installWallyPackages()
end
