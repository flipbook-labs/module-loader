local FlipbookBatteries = require("@luaupkg/flipbook-batteries")
local path = require("@std/path")
local process = require("@std/process")
local system = require("@std/system")

local cli = require("@scripts/batteries/cli")
local project = require("@repo/project")

local dotenv = FlipbookBatteries.dotenv
local run = FlipbookBatteries.run

dotenv()

local args = cli.parser()

args:add("apiKey", "option", {
	help = "Open Cloud API key used for running Luau Execution. Can also be "
		.. "supplied by the ROBLOX_API_KEY environment variable",
	aliases = { "k" },
})

args:add("filter", "option", {
	help = "Specify a filepath pattern to match for when running tests",
})

args:parse({ ... })

local apiKey = process.env.ROBLOX_API_KEY or args:get("apiKey")
if not apiKey then
	error(
		"A valid Open Cloud API key must be supplied with either the --apiKey flag or the ROBLOX_API_KEY environment variable"
	)
end

local filter = args:get("filter")

-- This gets picked up by the build step which uses Darklua to inject globals
process.env.JEST_TEST_PATH_PATTERN = if filter then filter else ""

local testPlacePath = path.join(system.tmpdir(), "tests.rbxl")

run("lute", { "run", "build", "--channel", "dev" })
run("rojo", { "build", project.ROJO_TESTS_PROJECT, "-o", testPlacePath })

local success, err = pcall(function()
	run("python3", {
		".lute/open-cloud/upload_and_run_task.py",
		testPlacePath,
		".lute/tasks/run-tests.luau",
	}, {
		env = {
			ROBLOX_UNIVERSE_ID = project.ROBLOX_UNIT_TESTING_UNIVERSE_ID,
			ROBLOX_PLACE_ID = project.ROBLOX_UNIT_TESTING_PLACE_ID,
			ROBLOX_API_KEY = tostring(apiKey),
		},
	})

	return nil
end)

assert(success, err)
