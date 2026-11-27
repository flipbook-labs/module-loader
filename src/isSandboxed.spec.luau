local JestGlobals = require("@pkg/JestGlobals")
local afterEach = JestGlobals.afterEach
local beforeEach = JestGlobals.beforeEach
local describe = JestGlobals.describe
local expect = JestGlobals.expect
local test = JestGlobals.test

local createModuleLoader = require("./createModuleLoader")
local isSandboxed = require("./isSandboxed")

local loader: typeof(createModuleLoader())
local moduleScripts: { ModuleScript } = {}

beforeEach(function()
	loader = createModuleLoader()
end)

afterEach(function()
	loader.clear()

	for _, moduleScript in moduleScripts do
		moduleScript:Destroy()
	end
	table.clear(moduleScripts)
end)

local function createModule(name: string, source: string): ModuleScript
	local moduleScript = Instance.new("ModuleScript")
	moduleScript.Name = name
	moduleScript.Source = source
	moduleScript.Parent = game
	table.insert(moduleScripts, moduleScript)
	return moduleScript
end

--[[
	A generated module can't name the real ModuleLoader package by path, so an
	ObjectValue passes the reference in. Requiring it through the loader runs
	the real package source in the sandbox, the same way a consumer's
	dependency graph would.
]]
local function createSandboxCheck(): ModuleScript
	local checkSandbox = createModule(
		"CheckSandbox",
		[[
			local ModuleLoader = require(script.ModuleLoaderScript.Value)
			return ModuleLoader.isSandboxed()
		]]
	)

	local moduleLoaderPointer = Instance.new("ObjectValue")
	moduleLoaderPointer.Name = "ModuleLoaderScript"
	moduleLoaderPointer.Value = script.Parent
	moduleLoaderPointer.Parent = checkSandbox

	return checkSandbox
end

describe("isSandboxed", function()
	test("returns false outside of a loader sandbox", function()
		expect(isSandboxed()).toBe(false)
	end)

	test("returns true inside a loader sandbox", function()
		expect(loader.require(createSandboxCheck())).toBe(true)
	end)

	test("returns true inside a sandbox after the loader is cleared", function()
		local checkSandbox = createSandboxCheck()

		loader.require(checkSandbox)
		loader.clear()

		expect(loader.require(checkSandbox)).toBe(true)
	end)

	test("finds the sandbox marker in the loader's _G but not in the real _G", function()
		local readMarker = createModule(
			"ReadMarker",
			[[
				return _G.__MODULE_LOADER_SANDBOX__
			]]
		)

		expect(loader.require(readMarker)).toBeDefined()
		expect(_G.__MODULE_LOADER_SANDBOX__).toBeUndefined()
	end)
end)
