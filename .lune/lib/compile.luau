local fs = require("@lune/fs")

local project = require("../../project")
local run = require("./run")

type Target = "prod" | "dev"

local function compile(target: Target)
	fs.writeDir(project.BUILD_PATH)

	run("rojo", {
		"sourcemap",
		project.ROJO_BUILD_PROJECT,
		"-o",
		project.DARKLUA_SOURCEMAP_PATH,
	})

	run("darklua", {
		"process",
		project.SOURCE_PATH,
		project.BUILD_PATH,
	})

	if target == "dev" then
		run("darklua", {
			"process",
			"example",
			`{project.BUILD_PATH}/Example`,
		})
	end
end

return compile
