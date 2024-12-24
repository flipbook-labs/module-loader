local process = require("@lune/process")

local compile = require("./lib/compile")
local parseArgs = require("./lib/parseArgs")
local project = require("../project")
local run = require("./lib/run")

local args = parseArgs(process.args)
local apiKey = assert(args.apiKey, "--apiKey must be supplied with a valid Open Cloud API key")

local testPlaceFile = "test-place.rbxl"

compile("dev")
run("rojo", { "build", project.ROJO_TESTS_PROJECT, "-o", testPlaceFile })

local output, success = run("python3", {
	".lune/open-cloud/upload_and_run_task.py",
	testPlaceFile,
	"tests/run-tests.luau",
}, {
	env = {
		ROBLOX_UNIVERSE_ID = "6599100156",
		ROBLOX_PLACE_ID = "123506190725771",
		ROBLOX_API_KEY = apiKey,
	},
})

run("rm", { testPlaceFile })

if not success then
	print(output)
	process.exit(1)
end
