--[[
	Publishes the built package to a registry.

	Usage:
	  lute run publish wally

	Build first with `lute run build --channel prod`. The `wally` target publishes
	the files `wally.toml` includes. When WALLY_REGISTRY_TOKEN is set, in the
	environment or in `.env`, it signs in with that token first, which replaces
	any token `wally login` saved before. Otherwise it uses the saved one.
]]
local FlipbookBatteries = require("@lpm/flipbook-batteries@v0.14.0")
local process = require("@std/process")

local cli = require("@scripts/batteries/cli")

local run = FlipbookBatteries.run

FlipbookBatteries.dotenv()

local args = cli.parser()
args:add("script", "positional", {
	help = "Path to the script being run. Provided automatically by Lute",
})
args:add("target", "positional", {
	help = `Where to publish: "wally"`,
	required = true,
})
args:parse({ ... })

local function publishToWally()
	local token = process.env.WALLY_REGISTRY_TOKEN
	if token ~= nil and token ~= "" then
		-- `run` prints each command it runs, which would put the token in the log.
		local login = process.run({
			"wally",
			"login",
			"--token",
			token,
		})
		assert(login.ok, `wally login failed: {login.stderr}`)
	end

	run("wally", { "publish" })
end

local PUBLISHERS: { [string]: () -> () } = {
	wally = publishToWally,
}

local target = assert(args:get("target"))
local publish = PUBLISHERS[target]
assert(publish, `bad value for target (must be "wally", got "{target}")`)

publish()
