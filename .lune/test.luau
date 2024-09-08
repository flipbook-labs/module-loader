local process = require("@lune/process")

local compile = require("./lib/compile")
local project = require("../project")
local run = require("./lib/run")
local setFlags = require("./lib/setFlags")

setFlags(process.os)
compile("dev")

run("rojo", { "build", project.ROJO_TESTS_PROJECT, "-o", "test-place.rbxl" })
run("run-in-roblox", { "--place", "test-place.rbxl", "--script", "tests/run-tests.luau" })
