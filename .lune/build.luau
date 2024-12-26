local compile = require("./lib/compile")
local parseArgs = require("./lib/parseArgs")
local process = require("@lune/process")
local project = require("../project")
local run = require("./lib/run")
local watch = require("./lib/watcher/watch")

local args = parseArgs(process.args)

local target = if args.target then args.target else "prod"
assert(target == "dev" or target == "prod", `bad value for target (must be one of "dev" or "prod", got "{target}")`)

local function build()
	run("rm", { "-rf", project.BUILD_PATH })
	compile(target)

	if target == "prod" then
		run("find", { project.BUILD_PATH, "-name", "*.spec.luau", "-type", "f", "-delete" })
	end
end

build()

if args.watch then
	watch({
		filePatterns = {
			"src/.*%.luau",
		},
		onChanged = build,
	})
end
