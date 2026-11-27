local JestGlobals = require("@pkg/JestGlobals")
local describe = JestGlobals.describe
local expect = JestGlobals.expect
local test = JestGlobals.test

local ModuleLoader = require("@root")

describe("createModuleLoader", function()
	test("makes a loader whose functions are called with a dot", function()
		local loader = ModuleLoader.createModuleLoader()
		local moduleScript = Instance.new("ModuleScript")
		moduleScript.Source = "return {}"

		local first = loader.require(moduleScript)
		expect(loader.require(moduleScript)).toBe(first)

		loader.clear()
		expect(loader.require(moduleScript)).never.toBe(first)

		local cached = {}
		local other = Instance.new("ModuleScript")
		loader.cache(other, cached)
		expect(loader.require(other)).toBe(cached)
	end)

	test("gives each loader its own cache", function()
		local moduleScript = Instance.new("ModuleScript")
		moduleScript.Source = "return {}"

		local a = ModuleLoader.createModuleLoader()
		local b = ModuleLoader.createModuleLoader()

		expect(a.require(moduleScript)).never.toBe(b.require(moduleScript))
	end)
end)
