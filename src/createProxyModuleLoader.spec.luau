local ReplicatedStorage = game:GetService("ReplicatedStorage")

local JestGlobals = require("@pkg/JestGlobals")
local test = JestGlobals.test
local expect = JestGlobals.expect
local describe = JestGlobals.describe
local beforeEach = JestGlobals.beforeEach
local afterEach = JestGlobals.afterEach

local createProxyModuleLoader = require("./createProxyModuleLoader")

type ModuleTestTree = {
	[string]: string | ModuleTestTree,
}
local function createModuleTest(tree: ModuleTestTree, parent: Instance?): Instance
	local root: Instance = if parent then parent else Instance.new("Folder")

	for name, sourceOrDescendants in tree do
		if typeof(sourceOrDescendants) == "table" then
			local folder = Instance.new("Folder")
			folder.Name = name
			folder.Parent = root

			createModuleTest(sourceOrDescendants :: ModuleTestTree, folder)
		else
			local module = Instance.new("ModuleScript")
			module.Name = name
			module.Source = sourceOrDescendants
			module.Parent = root
		end
	end

	if not parent then
		root.Parent = game
	end

	return root
end

local loader
local tree

beforeEach(function()
	loader = createProxyModuleLoader()
end)

afterEach(function()
	if tree then
		tree:Destroy()
	end
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
		loader.require(mockModuleInstance)

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
		loader.require(mockModuleInstance)

		expect(wasFired).toBe(false)

		mockModuleInstance.Source = "Something different"
		task.wait()

		expect(wasFired).toBe(true)
	end)

	test("fires for only the module that changed", function()
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

		local moduleA = tree:QueryDescendants("#ModuleA")[1] :: ModuleScript
		local moduleC = tree:QueryDescendants("#ModuleC")[1] :: ModuleScript

		loader.require(moduleC)

		moduleA.Source = "Changed"
		task.wait()

		expect(count).toBe(1)
	end)
end)

describe("loadModule", function()
	test("identities are always new", function()
		local moduleScript = Instance.new("ModuleScript")
		moduleScript.Source = "return function() end"

		local resultA = loader.loadModule(moduleScript)
		local resultB = loader.loadModule(moduleScript)

		expect(resultA).never.toBe(resultB)

		moduleScript.Source = "return {}"

		resultA = loader.loadModule(moduleScript)
		resultB = loader.loadModule(moduleScript)

		expect(resultA).never.toBe(resultB)
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

		local readGlobal = tree:QueryDescendants("#ReadGlobal")[1] :: ModuleScript
		local writeGlobal = tree:QueryDescendants("#WriteGlobal")[1] :: ModuleScript

		loader.loadModule(writeGlobal)

		local result = loader.loadModule(readGlobal)

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

		local useGlobal = tree:QueryDescendants("#UseGlobal")[1] :: ModuleScript

		local result = loader.loadModule(useGlobal)

		expect(result).toBe(true)
	end)

	test("supports instance requires from sub-modules", function()
		local root = Instance.new("ModuleScript")
		root.Source = [[
				return require("@self/SubModule")
			]]

		local subModule = Instance.new("ModuleScript")
		subModule.Name = "SubModule"
		subModule.Source = [[
				return require(script.Parent.Common)
			]]
		subModule.Parent = root

		local common = Instance.new("ModuleScript")
		common.Name = "Common"
		common.Source = [[
				return true
			]]
		common.Parent = root

		local result = loader.loadModule(root)

		expect(result).toBe(true)
	end)

	test("handles syntax errors for direct require", function()
		tree = createModuleTest({
			Module = [[
					syntax error
				]],
		})
		tree.Name = "SyntaxError"
		local module = tree:QueryDescendants("#Module")[1] :: ModuleScript

		expect(function()
			loader.loadModule(module)
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

		local consumer = tree:QueryDescendants("#Consumer")[1] :: ModuleScript

		expect(function()
			loader.loadModule(consumer)
		end).toThrow(`SyntaxError.Module3:1: Incomplete statement: expected assignment or a function call`)
	end)
end)

describe("require", function()
	test("caches identities between calls", function()
		local moduleScript = Instance.new("ModuleScript")
		moduleScript.Source = "return {}"

		local resultA = loader.require(moduleScript)
		local resultB = loader.require(moduleScript)

		expect(resultA).toBe(resultB)
	end)

	test("reuses cached dependencies across calls", function()
		tree = createModuleTest({
			Identity = [[
				return {}
			]],
			Consumer = [[
				return {
					Identity = require(script.Parent.Identity)
				}
			]],
		})

		local identityModule = tree:QueryDescendants("#Identity")[1] :: ModuleScript
		local consumerModule = tree:QueryDescendants("#Consumer")[1] :: ModuleScript

		local identityResult = loader.require(identityModule)
		local consumerResult = loader.require(consumerModule) :: { Identity: any }

		expect(consumerResult.Identity).toBe(identityResult)
	end)

	test("supports requires from sub-modules while cached", function()
		local root = Instance.new("ModuleScript")
		root.Source = [[
				return require("@self/SubModule")
			]]

		local subModule = Instance.new("ModuleScript")
		subModule.Name = "SubModule"
		subModule.Source = [[
				return require(script.Parent.Common)
			]]
		subModule.Parent = root

		local common = Instance.new("ModuleScript")
		common.Name = "Common"
		common.Source = [[
				return {}
			]]
		common.Parent = root

		local resultA = loader.require(root)
		local resultB = loader.require(root)

		expect(resultA).toBe(resultB)
	end)

	test("does not reuse loadModule sandboxes", function()
		local moduleScript = Instance.new("ModuleScript")
		moduleScript.Source = "return {}"

		local cachedResult = loader.require(moduleScript)
		local loadedResult = loader.loadModule(moduleScript)

		expect(loadedResult).never.toBe(cachedResult)
	end)

	test("clear() resets the cache", function()
		local moduleScript = Instance.new("ModuleScript")
		moduleScript.Source = "return {}"

		local resultA = loader.require(moduleScript)
		local resultB = loader.require(moduleScript)
		expect(resultA).toBe(resultB)

		loader.clear()

		local resultC = loader.require(moduleScript)
		expect(resultC).never.toBe(resultA)
	end)
end)

describe("string requires", function()
	test("supports @game", function()
		local moduleA = Instance.new("ModuleScript")
		moduleA.Name = "ModuleA"
		moduleA.Source = [[
				return require("@game/ReplicatedStorage/ModuleB")
			]]

		local moduleB = Instance.new("ModuleScript")
		moduleB.Name = "ModuleB"
		moduleB.Parent = ReplicatedStorage
		moduleB.Source = [[
				return true
			]]

		local result = loader.loadModule(moduleA)

		expect(result).toBe(true)

		moduleB:Destroy()
	end)

	test("supports @self", function()
		local root = Instance.new("ModuleScript")
		root.Source = [[
				return require("@self/Child")
			]]

		local child = Instance.new("ModuleScript")
		child.Name = "Child"
		child.Source = [[
				return true
			]]
		child.Parent = root

		local result = loader.loadModule(root)

		expect(result).toBe(true)
	end)

	test("supports relative paths from sub-modules", function()
		local root = Instance.new("ModuleScript")
		root.Source = [[
				return require("@self/SubModule")
			]]

		local subModule = Instance.new("ModuleScript")
		subModule.Name = "SubModule"
		subModule.Source = [[
				return require("./Common")
			]]
		subModule.Parent = root

		local common = Instance.new("ModuleScript")
		common.Name = "Common"
		common.Source = [[
				return true
			]]
		common.Parent = root

		local result = loader.loadModule(root)

		expect(result).toBe(true)
	end)

	test("supports relative paths", function()
		tree = createModuleTest(({
			Folder = {
				Module3 = [[
						return {}
					]],
				Folder = {
					Module2 = [[
							require("../Module3")
							return {}
						]],
				},
			},
			Module1 = [[
					require("./Folder/Folder/Module2")
					return {}
				]],
			Consumer = [[
					require("./Module1")
					return nil
				]],
		} :: any) :: ModuleTestTree)

		local consumer = tree:QueryDescendants("#Consumer")[1] :: ModuleScript

		loader.loadModule(consumer)
	end)
end)

describe("patch", function()
	test("allows patching return values of modules", function()
		tree = createModuleTest({
			ModuleA = [[
				return "Original"
			]],
			ModuleB = [[
				return require(script.Parent.ModuleA)
			]],
		})

		local moduleA = tree:QueryDescendants("#ModuleA")[1] :: ModuleScript
		local moduleB = tree:QueryDescendants("#ModuleB")[1] :: ModuleScript

		local resultA = loader.require(moduleA)
		local resultB = loader.require(moduleB)

		expect(resultA).toBe("Original")
		expect(resultB).toBe("Original")

		loader.patch(moduleA, "Patched")

		resultA = loader.require(moduleA)
		resultB = loader.require(moduleB)

		expect(resultA).toBe("Patched")
		expect(resultB).toBe("Patched")
	end)

	test("table identities remain consistent", function()
		local patchedIdentity = {}

		tree = createModuleTest({
			Identity = [[
				return {}
			]],
			Consumer = [[
				return {
					Identity = require(script.Parent.Identity)
				}
			]],
		})

		local identityModule = tree:QueryDescendants("#Identity")[1] :: ModuleScript
		local consumerModule = tree:QueryDescendants("#Consumer")[1] :: ModuleScript

		local identityResult = loader.require(identityModule)
		expect(identityResult).never.toBe(patchedIdentity)

		loader.patch(identityModule, patchedIdentity)

		identityResult = loader.require(identityModule)
		expect(identityResult).toBe(patchedIdentity)

		local consumerResult = loader.require(consumerModule) :: { Identity: any }
		expect(consumerResult.Identity).toBe(patchedIdentity)
	end)
end)
