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

run("lute", { "run", "build", "--channel", "dev" })

local success, err = pcall(function()
	run("rocale", {
		"run",
		"--script",
		".lute/tasks/run-tests.luau",
		"--load.project",
		project.ROJO_TESTS_PROJECT,
		"--output",
		`{system.tmpdir()}/tests.rbxl`,
		"--universeId",
		project.ROBLOX_UNIT_TESTING_UNIVERSE_ID,
		"--placeId",
		project.ROBLOX_UNIT_TESTING_PLACE_ID,
	}, {
		env = {
			ROBLOX_API_KEY = tostring(apiKey),
		},
	})

	return nil
end)

assert(success, err)
