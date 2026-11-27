local JestGlobals = require("@pkg/JestGlobals")
local describe = JestGlobals.describe
local expect = JestGlobals.expect
local test = JestGlobals.test

local ModuleLoader = require("@root")

describe("isModuleLoadError", function()
	test("accepts the error `require` raises when a module fails to load", function()
		local loader = ModuleLoader.createModuleLoader()
		local moduleScript = Instance.new("ModuleScript")
		moduleScript.Source = "error('boom')"

		local ok, err = pcall(loader.require, moduleScript)

		expect(ok).toBe(false)
		expect(ModuleLoader.isModuleLoadError(err)).toBe(true)
		expect((err :: { message: string }).message).toMatch("boom$")
	end)

	test("rejects a string, nil, and a table shaped like a ModuleLoadError", function()
		expect(ModuleLoader.isModuleLoadError("boom")).toBe(false)
		expect(ModuleLoader.isModuleLoadError(nil)).toBe(false)
		expect(ModuleLoader.isModuleLoadError({ message = "boom", traceback = "" })).toBe(false)
	end)
end)
