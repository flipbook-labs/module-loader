local JestGlobals = require("@pkg/JestGlobals")
local describe = JestGlobals.describe
local expect = JestGlobals.expect
local test = JestGlobals.test

local ModuleLoadError = require("./ModuleLoadError")
local createModuleLoader = require("./createModuleLoader")

describe("is", function()
	test("accepts the error `require` raises when a module fails to load", function()
		local loader = createModuleLoader()
		local moduleScript = Instance.new("ModuleScript")
		moduleScript.Source = "error('boom')"

		local ok, err = pcall(loader.require, moduleScript)

		expect(ok).toBe(false)
		expect(ModuleLoadError.is(err)).toBe(true)
		expect((err :: ModuleLoadError.ModuleLoadError).message).toMatch("boom$")
	end)

	test("rejects a string, nil, and a table shaped like a ModuleLoadError", function()
		expect(ModuleLoadError.is("boom")).toBe(false)
		expect(ModuleLoadError.is(nil)).toBe(false)
		expect(ModuleLoadError.is({ message = "boom", traceback = "" })).toBe(false)
	end)
end)
