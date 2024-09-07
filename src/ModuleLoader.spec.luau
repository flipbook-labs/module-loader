local ReplicatedStorage = game:GetService("ReplicatedStorage")

local JestGlobals = require("@pkg/JestGlobals")
local it = JestGlobals.it
local expect = JestGlobals.expect
local describe = JestGlobals.describe
local beforeEach = JestGlobals.beforeEach
local afterEach = JestGlobals.afterEach

local ModuleLoader = require("./ModuleLoader")

local function countDict(dict: { [string]: any })
	local count = 0
	for _ in pairs(dict) do
		count += 1
	end
	return count
end

type ModuleTestTree = {
	[string]: string | ModuleTestTree,
}
local testNumber = 0
local function createModuleTest(tree: ModuleTestTree, parent: Instance?): any
	testNumber += 1

	local root = Instance.new("Folder")
	root.Name = "ModuleTest" .. testNumber

	parent = if parent then parent else root

	for name, sourceOrDescendants in tree do
		if typeof(sourceOrDescendants) == "table" then
			createModuleTest(sourceOrDescendants, parent)
		else
			local module = Instance.new("ModuleScript")
			module.Name = name
			module.Source = sourceOrDescendants
			module.Parent = parent
		end
	end

	root.Parent = game

	return root
end

local mockModuleSource = {}
local loader: ModuleLoader.ModuleLoader
local tree

beforeEach(function()
	loader = ModuleLoader.new()
end)

afterEach(function()
	loader:clear()

	if tree then
		tree:Destroy()
	end
end)

describe("_getSource", function()
	-- This test doesn't supply much value. Essentially, the "Source"
	-- property requires elevated permissions, so we need the _getSource
	-- method so that that if tests are being run from within a normal
	-- script context that an error will not be produced.
	it("should return the Source property if it can be indexed", function()
		local mockModuleInstance = Instance.new("ModuleScript")

		local canIndex = pcall(function()
			return mockModuleInstance.Source
		end)

		local source = loader:_getSource(mockModuleInstance)

		if canIndex then
			expect(source).toBeDefined()
		else
			expect(source).toBeUndefined()
		end
	end)
end)

describe("_trackChanges", function()
	it("should create a Janitor instance if it doesn't exist", function()
		local mockModuleInstance = Instance.new("ModuleScript")

		expect(loader._janitors[mockModuleInstance.Name]).toBeUndefined()

		loader:_trackChanges(mockModuleInstance)

		expect(loader._janitors[mockModuleInstance.Name]).toBeDefined()
	end)

	it("should reuse the same Janitor instance for future calls", function()
		local mockModuleInstance = Instance.new("ModuleScript")

		loader:_trackChanges(mockModuleInstance)

		local janitor = loader._janitors[mockModuleInstance.Name]

		loader:_trackChanges(mockModuleInstance)

		expect(loader._janitors[mockModuleInstance.Name]).toBe(janitor)
	end)
end)

describe("loadedModuleChanged", function()
	it("should fire when a required module has its ancestry changed", function()
		local mockModuleInstance = Instance.new("ModuleScript")

		local wasFired = false

		-- Parent the ModuleScript somewhere in the DataModel so we can
		-- listen for AncestryChanged.
		mockModuleInstance.Parent = game

		loader.loadedModuleChanged:Connect(function(other: ModuleScript)
			if other == mockModuleInstance then
				wasFired = true
			end
		end)

		-- Require the module so that events get setup
		loader:require(mockModuleInstance)

		-- Trigger AncestryChanged to fire
		mockModuleInstance.Parent = nil

		expect(wasFired).toBe(true)
	end)

	it("should fire when a required module has its Source property change", function()
		local mockModuleInstance = Instance.new("ModuleScript")

		local wasFired = false
		loader.loadedModuleChanged:Connect(function(other: ModuleScript)
			if other == mockModuleInstance then
				wasFired = true
			end
		end)

		-- Require the module so that events get setup
		loader:require(mockModuleInstance)

		mockModuleInstance.Source = "Something different"

		expect(wasFired).toBe(true)
	end)

	it("should fire for every consumer up the chain", function()
		tree = createModuleTest({
			ModuleA = [[
					return "ModuleA"
				]],
			ModuleB = [[
					require(script.Parent.ModuleA)
					return "ModuleB"
				]],
			ModuleC = [[
					require(script.Parent.ModuleB)
					return "ModuleC"
				]],
		})

		local count = 0
		loader.loadedModuleChanged:Connect(function(module)
			for _, child in tree:GetChildren() do
				if module == child then
					count += 1
				end
			end
		end)

		loader:require(tree.ModuleC)

		tree.ModuleA.Source = "Changed"

		expect(count).toBe(3)
	end)
end)

describe("cache", function()
	it("should add a module and its result to the cache", function()
		local mockModuleInstance = Instance.new("ModuleScript")

		loader:cache(mockModuleInstance, mockModuleSource)

		local cachedModule = loader._cache[mockModuleInstance:GetFullName()]

		expect(cachedModule).toBeDefined()
		expect(cachedModule.result).toBe(mockModuleSource)
	end)
end)

describe("require", function()
	it("should add the module to the cache", function()
		local mockModuleInstance = Instance.new("ModuleScript")

		loader:require(mockModuleInstance)
		expect(loader._cache[mockModuleInstance:GetFullName()]).toBeDefined()
	end)

	it("should return cached results", function()
		tree = createModuleTest({
			-- We return a table since it can act as a unique symbol. So if
			-- both consumers are getting the same table we can perform an
			-- equality check
			SharedModule = [[
					local module = {}
					return module
				]],
			Consumer1 = [[
					local sharedModule = require(script.Parent.SharedModule)
					return sharedModule
				]],
			Consumer2 = [[
					local sharedModule = require(script.Parent.SharedModule)
					return sharedModule
				]],
		})

		local sharedModuleFromConsumer1 = loader:require(tree.Consumer1)
		local sharedModuleFromConsumer2 = loader:require(tree.Consumer2)

		expect(sharedModuleFromConsumer1).toBe(sharedModuleFromConsumer2)
	end)

	it("should add the calling script as a consumer", function()
		tree = createModuleTest({
			SharedModule = [[
					local module = {}
					return module
				]],
			Consumer = [[
					local sharedModule = require(script.Parent.SharedModule)
					return sharedModule
				]],
		})

		loader:require(tree.Consumer)

		local cachedModule = loader._cache[tree.SharedModule:GetFullName()]

		expect(cachedModule).toBeDefined()
		expect(cachedModule.consumers[tree.Consumer:GetFullName()]).toBeDefined()
	end)

	it("should update consumers when requiring a cached module from a different script", function()
		tree = createModuleTest({
			SharedModule = [[
					local module = {}
					return module
				]],
			Consumer1 = [[
					local sharedModule = require(script.Parent.SharedModule)
					return sharedModule
				]],
			Consumer2 = [[
					local sharedModule = require(script.Parent.SharedModule)
					return sharedModule
				]],
		})

		loader:require(tree.Consumer1)

		local cachedModule = loader._cache[tree.SharedModule:GetFullName()]

		expect(cachedModule.consumers[tree.Consumer1:GetFullName()]).toBeDefined()
		expect(cachedModule.consumers[tree.Consumer2:GetFullName()]).toBeUndefined()

		loader:require(tree.Consumer2)

		expect(cachedModule.consumers[tree.Consumer1:GetFullName()]).toBeDefined()
		expect(cachedModule.consumers[tree.Consumer2:GetFullName()]).toBeDefined()
	end)

	it("should keep track of _G between modules", function()
		tree = createModuleTest({
			WriteGlobal = [[
					_G.foo = true
					return nil
				]],
			ReadGlobal = [[
					return _G.foo
				]],
		})

		loader:require(tree.WriteGlobal)

		expect(loader._globals.foo).toBe(true)

		local result = loader:require(tree.ReadGlobal)

		expect(result).toBe(true)
	end)

	it("should keep track of _G in nested requires", function()
		tree = createModuleTest({
			DefineGlobal = [[
					_G.foo = true
					return nil
				]],
			UseGlobal = [[
					require(script.Parent.DefineGlobal)
					return _G.foo
				]],
		})

		local result = loader:require(tree.UseGlobal)

		expect(result).toBe(true)

		loader:clear()

		expect(loader._globals.foo).toBeUndefined()
	end)

	it("should add globals on _G to the cachedModule's globals", function()
		tree = createModuleTest({
			DefineGlobal = [[
					_G.foo = true
					return nil
				]],
		})

		loader:require(tree.DefineGlobal)

		local cachedModule = loader._cache[tree.DefineGlobal:GetFullName()]
		expect(cachedModule.globals.foo).toBe(true)
	end)
end)

describe("clearModule", function()
	it("should clear a module from the cache", function()
		tree = createModuleTest({
			Module = [[
					return "Module"
				]],
		})

		loader:require(tree.Module)

		expect(loader._cache[tree.Module:GetFullName()]).toBeDefined()

		loader:clearModule(tree.Module)

		expect(loader._cache[tree.Module:GetFullName()]).toBeUndefined()
	end)

	it("should clear all consumers of a module from the cache", function()
		tree = createModuleTest({
			SharedModule = [[
					local module = {}
					return module
				]],
			Consumer1 = [[
					local sharedModule = require(script.Parent.SharedModule)
					return sharedModule
				]],
			Consumer2 = [[
					local sharedModule = require(script.Parent.SharedModule)
					return sharedModule
				]],
		})

		loader:require(tree.Consumer1)
		loader:require(tree.Consumer2)

		expect(loader._cache[tree.Consumer1:GetFullName()]).toBeDefined()
		expect(loader._cache[tree.Consumer2:GetFullName()]).toBeDefined()
		expect(loader._cache[tree.SharedModule:GetFullName()]).toBeDefined()

		loader:clearModule(tree.SharedModule)

		expect(loader._cache[tree.Consumer1:GetFullName()]).toBeUndefined()
		expect(loader._cache[tree.Consumer2:GetFullName()]).toBeUndefined()
		expect(loader._cache[tree.SharedModule:GetFullName()]).toBeUndefined()
	end)

	it("should only clear modules in the consumer chain", function()
		tree = createModuleTest({
			Module = [[
					return nil
				]],
			Consumer = [[
					require(script.Parent.Module)
					return nil
				]],
			Independent = [[
					return nil
				]],
		})

		loader:require(tree.Consumer)
		loader:require(tree.Independent)

		expect(countDict(loader._cache)).toBe(3)

		loader:clearModule(tree.Module)

		expect(countDict(loader._cache)).toBe(1)
		expect(loader._cache[tree.Independent:GetFullName()]).toBeDefined()
	end)

	it("should clear all globals that a module supplied", function()
		tree = createModuleTest({
			DefineGlobalFoo = [[
					_G.foo = true
					return nil
				]],
			DefineGlobalBar = [[
					_G.bar = false
					return nil
				]],
		})

		loader:require(tree.DefineGlobalFoo)
		loader:require(tree.DefineGlobalBar)

		loader:clearModule(tree.DefineGlobalBar)

		expect(loader._globals.foo).toBeDefined()
		expect(loader._globals.bar).toBeUndefined()
	end)

	it("should fire loadedModuleChanged when clearing a module", function()
		tree = createModuleTest({
			Module = [[
					return nil
				]],
			Consumer = [[
					require(script.Parent.Module)
					return nil
				]],
		})

		local wasFired = false

		loader.loadedModuleChanged:Connect(function()
			wasFired = true
		end)

		loader:require(tree.Consumer)
		loader:clearModule(tree.Consumer)

		expect(wasFired).toBe(true)
	end)

	it("should fire loadedModuleChanged for every module up the chain", function()
		tree = createModuleTest({
			Module3 = [[
					return {}
				]],
			Module2 = [[
					require(script.Parent.Module3)
					return {}
				]],
			Module1 = [[
					require(script.Parent.Module2)
					return {}
				]],
			Consumer = [[
					require(script.Parent.Module1)
					return nil
				]],
		})

		local count = 0

		loader.loadedModuleChanged:Connect(function()
			count += 1
		end)

		loader:require(tree.Consumer)
		loader:clearModule(tree.Module3)

		expect(count).toBe(4)
	end)

	it("should not fire loadedModuleChanged for a module that hasn't been required", function()
		local wasFired = false

		loader.loadedModuleChanged:Connect(function()
			wasFired = true
		end)

		-- Do nothing if the module hasn't been cached
		local module = Instance.new("ModuleScript")
		loader:clearModule(module)
		expect(wasFired).toBe(false)
	end)
end)

describe("clear", function()
	it("should remove all modules from the cache", function()
		local mockModuleInstance = Instance.new("ModuleScript")

		loader:cache(mockModuleInstance, mockModuleSource)

		expect(countDict(loader._cache)).toBe(1)

		loader:clear()

		expect(countDict(loader._cache)).toBe(0)
	end)

	it("should reset globals", function()
		local globals = loader._globals

		loader:clear()

		expect(loader._globals).never.toBe(globals)
	end)
end)

describe("consumers", function()
	beforeEach(function()
		tree = createModuleTest({
			ModuleA = [[
					require(script.Parent.ModuleB)

					return "ModuleA"
				]],
			ModuleB = [[
					return "ModuleB"
				]],

			ModuleC = [[
					return "ModuleC"
				]],
		})
	end)

	it("should remove all consumers of a changed module from the cache", function()
		loader:require(tree.ModuleA)

		local hasItems = next(loader._cache) ~= nil
		expect(hasItems).toBe(true)

		tree.ModuleB.Source = 'return "ModuleB Reloaded"'
		task.wait()

		hasItems = next(loader._cache) ~= nil
		expect(hasItems).toBe(false)
	end)

	it("should not interfere with other cached modules", function()
		loader:require(tree.ModuleA)
		loader:require(tree.ModuleC)

		local hasItems = next(loader._cache) ~= nil
		expect(hasItems).toBe(true)

		tree.ModuleB.Source = 'return "ModuleB Reloaded"'
		task.wait()

		expect(loader._cache[tree.ModuleA:GetFullName()]).toBeUndefined()
		expect(loader._cache[tree.ModuleB:GetFullName()]).toBeUndefined()
		expect(loader._cache[tree.ModuleC:GetFullName()]).toBeDefined()
	end)
end)

describe("roblox-ts", function()
	local rbxtsInclude
	local mockRuntime

	beforeEach(function()
		rbxtsInclude = Instance.new("Folder")
		rbxtsInclude.Name = "rbxts_include"

		mockRuntime = Instance.new("ModuleScript")
		mockRuntime.Name = "RuntimeLib"
		mockRuntime.Source = [[
				local function import(...)
					return require(...)
				end
				return {
					import = import
				}
			]]
		mockRuntime.Parent = rbxtsInclude

		rbxtsInclude.Parent = ReplicatedStorage
	end)

	afterEach(function()
		loader:clear()
		rbxtsInclude:Destroy()
	end)

	it("clearModule() should never clear the roblox-ts runtime from the cache", function()
		-- This example isn't quite how a roblox-ts project would be setup
		-- in practice since the require's for `Shared` would be using
		-- `TS.import`, but it should be close enough for our test case
		tree = createModuleTest({
			Shared = [[
					local TS = require(game:GetService("ReplicatedStorage").rbxts_include.RuntimeLib)
					return {}
				]],
			Module1 = [[
					local TS = require(game:GetService("ReplicatedStorage").rbxts_include.RuntimeLib)
					local Shared = TS.import(script.Parent.Shared)
					return nil
				]],
			Module2 = [[
					local TS = require(game:GetService("ReplicatedStorage").rbxts_include.RuntimeLib)
					local Shared = TS.import(script.Parent.Shared)
					return nil
				]],
			Root = [[
					local TS = require(game:GetService("ReplicatedStorage").rbxts_include.RuntimeLib)
					local Module1 = TS.import(script.Parent.Module1)
					local Module2 = TS.import(script.Parent.Module2)
				]],
		})

		loader:require(tree.Root)
		loader:clearModule(tree.Shared)

		expect(loader._cache[mockRuntime:GetFullName()]).toBeDefined()
		expect(loader._cache[tree.Shared:GetFullName()]).toBeUndefined()
		expect(loader._cache[tree.Module1:GetFullName()]).toBeUndefined()
		expect(loader._cache[tree.Module2:GetFullName()]).toBeUndefined()
		expect(loader._cache[tree.Root:GetFullName()]).toBeUndefined()
	end)

	it("clear() should clear the roblox-ts runtime when calling", function()
		tree = createModuleTest({
			Module = [[
					local TS = require(game:GetService("ReplicatedStorage").rbxts_include.RuntimeLib)
				]],
		})

		loader:require(tree.Module)
		loader:clear()

		expect(loader._cache[mockRuntime:GetFullName()]).toBeUndefined()
		expect(loader._cache[tree.Module:GetFullName()]).toBeUndefined()
	end)
end)
