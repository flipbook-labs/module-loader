local JestGlobals = require("@pkg/JestGlobals")
local describe = JestGlobals.describe
local expect = JestGlobals.expect
local test = JestGlobals.test

local ModuleLoader = require("./ModuleLoader")

describe("isLoadError", function()
	test("accepts the error `require` raises when a module fails to load", function()
		local loader = ModuleLoader.new()
		local moduleScript = Instance.new("ModuleScript")
		moduleScript.Source = "error('boom')"

		local ok, err = pcall(function()
			return loader:require(moduleScript)
		end)

		expect(ok).toBe(false)
		expect(ModuleLoader.isLoadError(err)).toBe(true)
		expect((err :: { message: string }).message).toMatch("boom$")
	end)

	test("rejects a string, nil, and a table shaped like a LoadError", function()
		expect(ModuleLoader.isLoadError("boom")).toBe(false)
		expect(ModuleLoader.isLoadError(nil)).toBe(false)
		expect(ModuleLoader.isLoadError({ message = "boom", traceback = "" })).toBe(false)
	end)
end)
