local JestGlobals = require("@pkg/JestGlobals")
local test = JestGlobals.test
local expect = JestGlobals.expect

local getEnv = require("./getEnv")

test("returns a table", function()
	expect(typeof(getEnv())).toBe("table")
end)

test("has the correct 'script' global", function()
	local env = getEnv(script.Parent.getEnv)
	expect(env.script).toBe(script.Parent.getEnv)
end)

test("sets _G to the 'globals' argument", function()
	local globals = {}
	local env = getEnv(script.Parent.getEnv, globals)

	expect(env._G).toBeDefined()
	expect(env._G).toBe(globals)
	-- selene: allow(global_usage)
	expect(env._G).never.toBe(_G)
end)
