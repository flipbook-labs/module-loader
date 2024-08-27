local JestGlobals = require("@pkg/JestGlobals")
local it = JestGlobals.it
local expect = JestGlobals.expect

local getEnv = require("./getEnv")

it("should return a table", function()
	expect(typeof(getEnv())).toBe("table")
end)

it("should have the correct 'script' global", function()
	local env = getEnv(script.Parent.getEnv)
	expect(env.script).toBe(script.Parent.getEnv)
end)

it("should set _G to the 'globals' argument", function()
	local globals = {}
	local env = getEnv(script.Parent.getEnv, globals)

	expect(env._G).toBeDefined()
	expect(env._G).toBe(globals)
	-- selene: allow(global_usage)
	expect(env._G).never.toBe(_G)
end)
