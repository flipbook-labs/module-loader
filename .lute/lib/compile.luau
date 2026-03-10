local fs = require("@lune/fs")
local project = require("@repo/project")

local run = require("./run")

local function compile()
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
end

return compile
