local compile = require("./lib/compile")
local parseArgs = require("./lib/parseArgs")
local process = require("@lune/process")
local project = require("../project")
local run = require("./lib/run")
local watch = require("./lib/watcher/watch")

local args = parseArgs(process.args)

local target = if args.target then args.target else "prod"

local function build()
	run("rm", { "-rf", project.BUILD_PATH })
	compile(target)

	if target == "prod" then
		run("rm", { "-rf", `{project.BUILD_PATH}/**/*.spec.luau` })
	end
end

build()

if args.watch then
	watch({
		filePatterns = {
			"src/.*%.luau",
			"example/.*%.luau",
		},
		onChanged = build,
	})
end
