local ReplicatedStorage = game:GetService("ReplicatedStorage")

local JestGlobals = require("@pkg/JestGlobals")
local test = JestGlobals.test
local expect = JestGlobals.expect
local describe = JestGlobals.describe
local beforeEach = JestGlobals.beforeEach
local afterEach = JestGlobals.afterEach
local describeEach = describe.each :: any

local ModuleLoader = require("./ModuleLoader")

local loadModuleEnabled = pcall(function()
	return debug["loadmodule"](Instance.new("ModuleScript"))
end)

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

describeEach({
	"loadstring",
	"loadmodule",
})("%s", function(loadingStrategy)
	if loadingStrategy == "loadmodule" and not loadModuleEnabled then
		test = test.skip
	end

	beforeEach(function()
		loader = ModuleLoader.new()
		loader._forceLoadstring = loadingStrategy == "loadstring"
	end)

	afterEach(function()
		loader:clear()

		if tree then
			tree:Destroy()
		end
	end)

	describe("_trackChanges", function()
		test("creates a Janitor instance if it doesn't exist", function()
			local mockModuleInstance = Instance.new("ModuleScript")
			mockModuleInstance.Source = "return nil"

			expect(loader._janitors[mockModuleInstance]).toBeUndefined()

			loader:_trackChanges(mockModuleInstance)

			expect(loader._janitors[mockModuleInstance]).toBeDefined()
		end)

		test("reuses the same Janitor instance for future calls", function()
			local mockModuleInstance = Instance.new("ModuleScript")
			mockModuleInstance.Source = "return nil"

			loader:_trackChanges(mockModuleInstance)

			local janitor = loader._janitors[mockModuleInstance]

			loader:_trackChanges(mockModuleInstance)

			expect(loader._janitors[mockModuleInstance]).toBe(janitor)
		end)
	end)

	describe("loadedModuleChanged", function()
		test("fires when a required module has its ancestry changed", function()
			local mockModuleInstance = Instance.new("ModuleScript")
			mockModuleInstance.Source = "return nil"

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

			expect(wasFired).toBe(false)

			-- Trigger AncestryChanged to fire
			mockModuleInstance.Parent = nil

			expect(wasFired).toBe(true)
		end)

		test("fires when a required module has its Source property change", function()
			local mockModuleInstance = Instance.new("ModuleScript")
			mockModuleInstance.Source = "return nil"

			local wasFired = false
			loader.loadedModuleChanged:Connect(function(other: ModuleScript)
				if other == mockModuleInstance then
					wasFired = true
				end
			end)

			-- Require the module so that events get setup
			loader:require(mockModuleInstance)

			expect(wasFired).toBe(false)

			mockModuleInstance.Source = "Something different"

			expect(wasFired).toBe(true)
		end)

		test("fires for every consumer up the chain", function()
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
		test("adds a module and its result to the cache", function()
			local mockModuleInstance = Instance.new("ModuleScript")
			mockModuleInstance.Source = "return nil"

			loader:cache(mockModuleInstance, mockModuleSource)

			local loadedModule = loader._moduleRegistry.getByInstance(mockModuleInstance)

			assert(loadedModule, "loaded module undefined")
			expect(loadedModule.exports).toBe(mockModuleSource)
		end)
	end)

	describe("require", function()
		test("adds the module to the cache", function()
			local mockModuleInstance = Instance.new("ModuleScript")
			mockModuleInstance.Source = "return nil"

			loader:require(mockModuleInstance)
			expect(loader._moduleRegistry.getByInstance(mockModuleInstance)).toBeDefined()
		end)

		test("keeps track of module dependencies", function()
			tree = createModuleTest({
				Module3 = [[
					return nil
				]],
				Module2 = [[
					require(script.Parent.Module3)
					return nil
				]],
				Module1 = [[
					require(script.Parent.Module2)
					return nil
				]],
				Root = [[
					require(script.Parent.Module1)
					return nil
				]],
			})

			loader:require(tree.Root)

			expect(loader._moduleRegistry.getByInstance(tree.Root)).toMatchObject({
				dependencies = {
					[tree.Module1] = true,
				},
			})
			expect(loader._moduleRegistry.getByInstance(tree.Module1)).toMatchObject({
				dependencies = {
					[tree.Module2] = true,
				},
			})
			expect(loader._moduleRegistry.getByInstance(tree.Module2)).toMatchObject({
				dependencies = {
					[tree.Module3] = true,
				},
			})
			expect(loader._moduleRegistry.getByInstance(tree.Module3)).toMatchObject({
				dependencies = {},
			})
		end)

		test("returns cached results", function()
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

		test("adds the calling script as a consumer", function()
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

			local loadedModule = loader._moduleRegistry.getByInstance(tree.SharedModule)
			assert(loadedModule, "loaded module undefined")
			expect(loadedModule.consumers[tree.Consumer]).toBeDefined()
		end)

		test("updates consumers when requiring a cached module from a different script", function()
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

			local loadedModule = loader._moduleRegistry.getByInstance(tree.SharedModule)

			assert(loadedModule, "loaded module undefined")

			expect(loadedModule.consumers[tree.Consumer1]).toBeDefined()
			expect(loadedModule.consumers[tree.Consumer2]).toBeUndefined()

			loader:require(tree.Consumer2)

			expect(loadedModule.consumers[tree.Consumer1]).toBeDefined()
			expect(loadedModule.consumers[tree.Consumer2]).toBeDefined()
		end)

		test("keeps track of _G between modules", function()
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

			local result = loader:require(tree.ReadGlobal)

			expect(result).toBe(true)
		end)

		test("keeps track of _G in nested requires", function()
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
		end)

		test("handles syntax errors for direct require", function()
			tree = createModuleTest({
				Module = [[
					syntax error
				]],
			})
			tree.Name = "SyntaxError"

			expect(function()
				loader:require(tree.Module)
			end).toThrow(`SyntaxError.Module:1: Incomplete statement: expected assignment or a function call`)
		end)

		test("handles syntax errors for nested requires", function()
			tree = createModuleTest({
				Module3 = [[
					syntax error
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
			tree.Name = "SyntaxError"

			expect(function()
				loader:require(tree.Consumer)
			end).toThrow(`SyntaxError.Module3:1: Incomplete statement: expected assignment or a function call`)
		end)
	end)

	describe("clearModule", function()
		test("clears a module from the cache", function()
			tree = createModuleTest({
				Module = [[
					return "Module"
				]],
			})

			loader:require(tree.Module)

			expect(loader._moduleRegistry.getByInstance(tree.Module)).toBeDefined()

			loader:clearModule(tree.Module)

			expect(loader._moduleRegistry.getByInstance(tree.Module)).toBeUndefined()
		end)

		test("clears all consumers of a module from the cache", function()
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

			expect(loader._moduleRegistry.getByInstance(tree.Consumer1)).toBeDefined()
			expect(loader._moduleRegistry.getByInstance(tree.Consumer2)).toBeDefined()
			expect(loader._moduleRegistry.getByInstance(tree.SharedModule)).toBeDefined()

			loader:clearModule(tree.SharedModule)

			expect(loader._moduleRegistry.getByInstance(tree.Consumer1)).toBeUndefined()
			expect(loader._moduleRegistry.getByInstance(tree.Consumer2)).toBeUndefined()
			expect(loader._moduleRegistry.getByInstance(tree.SharedModule)).toBeUndefined()
		end)

		test("only clears modules in the consumer chain", function()
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

			expect(#loader._moduleRegistry.getAllModules()).toBe(3)

			loader:clearModule(tree.Module)

			expect(#loader._moduleRegistry.getAllModules()).toBe(1)
			expect(loader._moduleRegistry.getByInstance(tree.Independent)).toBeDefined()
		end)

		test("fires loadedModuleChanged when clearing a module", function()
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

		test("fires loadedModuleChanged for every module up the chain", function()
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

		test("never fires loadedModuleChanged for a module that hasn't been required", function()
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
		test("removes all modules from the cache", function()
			local mockModuleInstance = Instance.new("ModuleScript")
			mockModuleInstance.Source = "return nil"

			loader:cache(mockModuleInstance, mockModuleSource)

			expect(#loader._moduleRegistry.getAllModules()).toBe(1)

			loader:clear()

			expect(#loader._moduleRegistry.getAllModules()).toBe(0)
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

		test("removes all consumers of a changed module from the cache", function()
			loader:require(tree.ModuleA)

			local hasItems = next(loader._moduleRegistry.getAllModules()) ~= nil
			expect(hasItems).toBe(true)

			tree.ModuleB.Source = 'return "ModuleB Reloaded"'
			task.wait()

			hasItems = next(loader._moduleRegistry.getAllModules()) ~= nil
			expect(hasItems).toBe(false)
		end)

		test("does not interfere with other cached modules", function()
			loader:require(tree.ModuleA)
			loader:require(tree.ModuleC)

			local hasItems = next(loader._moduleRegistry.getAllModules()) ~= nil
			expect(hasItems).toBe(true)

			tree.ModuleB.Source = 'return "ModuleB Reloaded"'
			task.wait()

			expect(loader._moduleRegistry.getByInstance(tree.ModuleA)).toBeUndefined()
			expect(loader._moduleRegistry.getByInstance(tree.ModuleB)).toBeUndefined()
			expect(loader._moduleRegistry.getByInstance(tree.ModuleC)).toBeDefined()
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

		test("clearModule() never clears the roblox-ts runtime from the cache", function()
			-- This example isn't quite how a roblox-ts project would be setup since
			-- the requires for `Shared` would be using `TS.import`, but it should
			-- be close enough for our test case
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

					return nil
				]],
			})

			loader:require(tree.Root)
			loader:clearModule(tree.Shared)

			expect(loader._moduleRegistry.getByInstance(mockRuntime)).toBeDefined()
			expect(loader._moduleRegistry.getByInstance(tree.Shared)).toBeUndefined()
			expect(loader._moduleRegistry.getByInstance(tree.Module1)).toBeUndefined()
			expect(loader._moduleRegistry.getByInstance(tree.Module2)).toBeUndefined()
			expect(loader._moduleRegistry.getByInstance(tree.Root)).toBeUndefined()
		end)

		test("clear() clears the roblox-ts runtime when calling", function()
			tree = createModuleTest({
				Module = [[
					local TS = require(game:GetService("ReplicatedStorage").rbxts_include.RuntimeLib)
					return nil
				]],
			})

			loader:require(tree.Module)
			loader:clear()

			expect(loader._moduleRegistry.getByInstance(mockRuntime)).toBeUndefined()
			expect(loader._moduleRegistry.getByInstance(tree.Module)).toBeUndefined()
		end)
	end)
end)
