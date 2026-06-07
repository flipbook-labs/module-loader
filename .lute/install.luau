local process = require("@std/process")

local project = require("@repo/project")

-- Install Loom dependencies first since the rest of the script depends on them.
-- Loom installs into a global store (~/.loom/store), which the @luaupkg alias in
-- .luaurc resolves against, so there's nothing to copy into the project.
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
