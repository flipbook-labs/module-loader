local ReplicatedStorage = game:GetService("ReplicatedStorage")

local JestGlobals = require("@pkg/JestGlobals")
local test = JestGlobals.test
local expect = JestGlobals.expect
local describe = JestGlobals.describe
local beforeEach = JestGlobals.beforeEach
local afterEach = JestGlobals.afterEach

local createModuleLoader = require("./createModuleLoader")

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

local function createSpyRequire(shouldError: boolean, errorMessage: string?)
	local callCount = 0
	local currentErrorMessage = errorMessage or "Cannot require a non-RobloxScript module from a RobloxScript"

	local function spyRequire(_: ModuleScript)
		callCount += 1
		if shouldError then
			error(currentErrorMessage, 2)
		end
		return (require :: any)(_)
	end

	return {
		fn = spyRequire,
		getCallCount = function()
			return callCount
		end,
		reset = function()
			callCount = 0
		end,
	}
end

local function createFakeLoadmodule(exports: any?)
	local cleanupCalls = 0
	local cleanupFn = function()
		cleanupCalls += 1
	end

	local function fakeLoadmodule(_: ModuleScript)
		local chunk = function()
			return exports or "mocked export"
		end
		return chunk, nil, cleanupFn
	end

	return {
		fn = fakeLoadmodule,
		getCleanupCallCount = function()
			return cleanupCalls
		end,
	}
end

-- Returns (nil, nil) to force the tmpScript path, simulating loadstring being
-- unavailable.
local function forceTmpScriptPath(_source: string, _chunkName: string)
	return nil, nil
end

local mockModuleSource = {}
local loader
local moduleRegistry
local tree

beforeEach(function()
	loader = createModuleLoader()

	moduleRegistry = loader._getModuleRegistry()
end)

afterEach(function()
	loader.clear()

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

	test("fires only for the module that changed", function()
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

describe("cache", function()
	test("adds a module and its result to the cache", function()
		local mockModuleInstance = Instance.new("ModuleScript")
		local mockReturnValues = { foo = true }

		loader.cache(mockModuleInstance, mockReturnValues)

		local result = loader.require(mockModuleInstance)

		expect(result).toBe(mockReturnValues)
	end)

	test("works with multiple return values", function()
		local mockModuleInstance = Instance.new("ModuleScript")

		loader.cache(mockModuleInstance, true, false)

		local first, second = loader.require(mockModuleInstance)

		expect(first).toBe(true)
		expect(second).toBe(false)
	end)
end)

describe("require", function()
	test("adds the module to the cache", function()
		local mockModuleInstance = Instance.new("ModuleScript")
		mockModuleInstance.Source = "return nil"

		loader.require(mockModuleInstance)
		expect(moduleRegistry.getByInstance(mockModuleInstance)).toBeDefined()
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

		local consumer1 = tree:QueryDescendants("#Consumer1")[1] :: ModuleScript
		local consumer2 = tree:QueryDescendants("#Consumer2")[1] :: ModuleScript

		expect(loader.require(consumer1)).toBe(loader.require(consumer2))
	end)

	describe("circular dependencies", function()
		test("throws when a module requires itself", function()
			local moduleScript = Instance.new("ModuleScript")
			moduleScript.Source = [[
				return require(script)
			]]

			expect(function()
				loader.require(moduleScript)
			end).toThrow("Requested module was required recursively")
		end)

		test("throws when an indirect cycle is detected", function()
			type ModuleA = {
				Name: string,
				ModuleB: ModuleB,
			}

			type ModuleB = {
				Name: string,
				ModuleA: ModuleA,
			}

			tree = createModuleTest({
				ModuleA = [[
					local ModuleB = require(script.Parent.ModuleB)
					return {
						Name = "ModuleA",
						ModuleB = ModuleB,
					}
				]],
				ModuleB = [[
					local ModuleA = require(script.Parent.ModuleA)
					return {
						Name = "ModuleB",
						ModuleA = ModuleA,
					}
				]],
			})

			local moduleA = tree:QueryDescendants("#ModuleA")[1] :: ModuleScript

			expect(function()
				loader.require(moduleA)
			end).toThrow("Requested module was required recursively")
		end)

		test("throws when a circular string require is detected", function()
			type ModuleA = {
				Name: string,
				ModuleB: ModuleB,
			}

			type ModuleB = {
				Name: string,
				ModuleA: ModuleA,
			}

			tree = createModuleTest({
				ModuleA = [[
					local ModuleB = require("./ModuleB")
					return {
						Name = "ModuleA",
						ModuleB = ModuleB,
					}
				]],
				ModuleB = [[
					local ModuleA = require("./ModuleA")
					return {
						Name = "ModuleB",
						ModuleA = ModuleA,
					}
				]],
			})

			local moduleA = tree:QueryDescendants("#ModuleA")[1] :: ModuleScript

			expect(function()
				loader.require(moduleA)
			end).toThrow("Requested module was required recursively")
		end)
	end)

	describe("globals", function()
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

			loader.require(writeGlobal)

			local result = loader.require(readGlobal)

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

			local result = loader.require(useGlobal)

			expect(result).toBe(true)
		end)

		test("clearing the cache also clears _G", function()
			tree = createModuleTest({
				WriteGlobal = [[
					_G.foo = true
					return nil
				]],
				ReadGlobal = [[
					return _G.foo
				]],
			})

			local writeGlobal = tree:QueryDescendants("#WriteGlobal")[1] :: ModuleScript
			local readGlobal = tree:QueryDescendants("#ReadGlobal")[1] :: ModuleScript

			loader.require(writeGlobal)

			expect(_G.foo).toBeUndefined()
			expect(loader.require(readGlobal)).toBe(true)

			loader.clear()

			expect(_G.foo).toBeUndefined()
			expect(loader.require(readGlobal)).toBe(nil)
		end)

		test("clearing _G only clears values set by sandboxed modules", function()
			tree = createModuleTest({
				SandboxedModule = [[
					_G.foo = true
					return nil
				]],
				ModuleRequiredNormally = [[
					_G.bar = true
					return nil
				]],
				ReadGlobal = [[
					return _G.foo
				]],
			})

			local sandboxedModule = tree:QueryDescendants("#SandboxedModule")[1] :: ModuleScript
			local readGlobal = tree:QueryDescendants("#ReadGlobal")[1] :: ModuleScript
			local moduleRequiredNormally = tree:QueryDescendants("#ModuleRequiredNormally")[1] :: ModuleScript

			loader.require(sandboxedModule)

			expect(loader.require(readGlobal)).toBe(true)
			expect(_G.bar).toBeUndefined();
			(require :: any)(moduleRequiredNormally)

			expect(loader.require(readGlobal)).toBe(true)
			expect(_G.bar).toBe(true)

			loader.clear()

			expect(loader.require(readGlobal)).toBeUndefined()
			expect(_G.bar).toBe(true)

			_G.bar = nil
		end)

		test("_G in the sandbox inherits from the real _G, but does not pollute it when written to", function()
			tree = createModuleTest({
				WriteGlobal = [[
					_G.foo = false
					_G.bar = true
					return nil
				]],
				ReadGlobal = [[
					return _G.foo, _G.bar
				]],
			})

			local writeGlobal = tree:QueryDescendants("#WriteGlobal")[1] :: ModuleScript
			local readGlobal = tree:QueryDescendants("#ReadGlobal")[1] :: ModuleScript

			_G.foo = true

			expect(_G.foo).toBe(true)
			expect(_G.bar).toBeUndefined()

			loader.require(writeGlobal)

			expect(_G.foo).toBe(true)
			expect(_G.bar).toBeUndefined()

			local foo, bar = loader.require(readGlobal)
			expect(foo).toBe(false)
			expect(bar).toBe(true)

			expect(_G.foo).toBe(true)
			expect(_G.bar).toBeUndefined()

			loader.clear()

			expect(_G.foo).toBe(true)
			expect(_G.bar).toBeUndefined()

			_G.foo = nil
		end)

		describe("variable persistence in global module scope", function()
			test("keeps track of bare globals between modules", function()
				local moduleScript = Instance.new("ModuleScript")
				moduleScript.Source = [[
					local value = true

					local function getValue()
						return value
					end

					local function setValue(newValue: boolean)
						value = newValue
					end

					return {
						getValue = getValue,
						setValue = setValue,
					}
				]]

				local result = loader.require(moduleScript) :: { getValue: () -> boolean, setValue: (boolean) -> () }

				expect(result.getValue()).toBe(true)

				result.setValue(false)

				expect(result.getValue()).toBe(false)

				loader.clear()

				result = loader.require(moduleScript) :: { getValue: () -> boolean, setValue: (boolean) -> () }
				expect(result.getValue()).toBe(true)
			end)
		end)
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
			loader.require(module)
		end).toThrow("Incomplete statement: expected assignment or a function call")
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
			loader.require(consumer)
		end).toThrow("Incomplete statement: expected assignment or a function call")
	end)

	test("changes to a module's source requires clearing the cache to use the new result", function()
		local moduleScript = Instance.new("ModuleScript")
		moduleScript.Source = "return true"

		expect(loader.require(moduleScript)).toBe(true)

		moduleScript.Source = "return false"

		expect(loader.require(moduleScript)).toBe(true)

		loader.clear()

		expect(loader.require(moduleScript)).toBe(false)
	end)

	test("modules with a type that includes '...' can be required", function()
		local moduleScript = Instance.new("ModuleScript")
		moduleScript.Source = [[
			local Class = {}

			function Class.new(param: string)
				return {}
			end

			export type Class = typeof(Class.new(...))
		]]

		expect(function()
			loader.require(moduleScript)
		end).never.toThrow()
	end)

	test("modules bumping up against the 200 locals limit can still be required", function()
		local moduleScript = Instance.new("ModuleScript")
		moduleScript.Source = ""
		for i = 1, 200 do
			moduleScript.Source ..= `local var{i} = {i}\n`
		end

		expect(function()
			loader.require(moduleScript)
		end).never.toThrow()
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

			local result = loader.require(moduleA)

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

			local result = loader.require(root)

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

			loader.require(consumer)
		end)
	end)
end)

describe("clear", function()
	test("removes all modules from the cache", function()
		local mockModuleInstance = Instance.new("ModuleScript")
		mockModuleInstance.Source = "return nil"

		loader.cache(mockModuleInstance, mockModuleSource)

		expect(#moduleRegistry.getAllModules()).toBe(1)

		loader.clear()

		expect(#moduleRegistry.getAllModules()).toBe(0)
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
		loader.clear()
		rbxtsInclude:Destroy()
	end)

	test("clear() clears the roblox-ts runtime when calling", function()
		tree = createModuleTest({
			Module = [[
				local TS = require(game:GetService("ReplicatedStorage").rbxts_include.RuntimeLib)
				return nil
			]],
		})

		local module = tree:QueryDescendants("#Module")[1] :: ModuleScript

		loader.require(module)
		loader.clear()

		expect(moduleRegistry.getByInstance(mockRuntime)).toBeUndefined()
		expect(moduleRegistry.getByInstance(module)).toBeUndefined()
	end)
end)

describe("debug.loadmodule seam integration (simulated non-RobloxScript paths)", function()
	-- These tests simulate the non-RobloxScript context and debug.loadmodule
	-- paths by injecting dependencies. The real security context and FFlag are
	-- only accessible in internal Flipbook (LocalScript-context storybooks), but
	-- the logic is fully exercised here.

	test("falls back to debug.loadmodule when require throws NON_ROBLOXSCRIPT_ERROR", function()
		local testModule = Instance.new("ModuleScript")
		testModule.Source = "return 42"

		local spyRequire = createSpyRequire(true, "Cannot require a non-RobloxScript module from a RobloxScript")
		local fakeLoadmodule = createFakeLoadmodule(99)

		loader = createModuleLoader({
			require = spyRequire.fn,
			loadmodule = fakeLoadmodule.fn,
			getSource = function(ms: ModuleScript)
				return ms.Source
			end,
			compile = forceTmpScriptPath,
		})

		local result = loader.require(testModule)

		-- Should get the mocked loadmodule export (99), not the source (42).
		expect(result).toBe(99)
	end)

	test("skips require attempt after detecting non-RobloxScript context (lazy)", function()
		tree = createModuleTest({
			Module1 = "return 1",
			Module2 = "return 2",
		})

		local module1 = tree:QueryDescendants("#Module1")[1] :: ModuleScript
		local module2 = tree:QueryDescendants("#Module2")[1] :: ModuleScript

		local spyRequire = createSpyRequire(true, "Cannot require a non-RobloxScript module from a RobloxScript")
		local fakeLoadmodule = createFakeLoadmodule()

		loader = createModuleLoader({
			require = spyRequire.fn,
			loadmodule = fakeLoadmodule.fn,
			getSource = function(ms: ModuleScript)
				return ms.Source
			end,
			compile = forceTmpScriptPath,
		})

		-- Load module 1: require will be called and throw, then fall back to loadmodule.
		loader.require(module1)
		expect(spyRequire.getCallCount()).toBe(1)

		-- Reset spy to test second load.
		spyRequire.reset()

		-- Load module 2: require should NOT be called (context already detected as non-RobloxScript).
		loader.require(module2)

		-- Spy should not have been called for the second module.
		expect(spyRequire.getCallCount()).toBe(0)
	end)

	test("accumulates and flushes debug.loadmodule cleanup functions", function()
		tree = createModuleTest({
			Module1 = "return 1",
			Module2 = "return 2",
		})

		local module1 = tree:QueryDescendants("#Module1")[1] :: ModuleScript
		local module2 = tree:QueryDescendants("#Module2")[1] :: ModuleScript

		local spyRequire = createSpyRequire(true, "Cannot require a non-RobloxScript module from a RobloxScript")
		local fakeLoadmodule = createFakeLoadmodule()

		loader = createModuleLoader({
			require = spyRequire.fn,
			loadmodule = fakeLoadmodule.fn,
			getSource = function(ms: ModuleScript)
				return ms.Source
			end,
			compile = forceTmpScriptPath,
		})

		-- Load two modules; each should accumulate one cleanup.
		loader.require(module1)
		loader.require(module2)

		-- Cleanups not yet called.
		expect(fakeLoadmodule.getCleanupCallCount()).toBe(0)

		-- Clear flushes all accumulated cleanups.
		loader.clear()

		-- Both cleanups should have fired.
		expect(fakeLoadmodule.getCleanupCallCount()).toBe(2)
	end)

	test("throws informative error when non-RobloxScript but debug.loadmodule unavailable", function()
		local testModule = Instance.new("ModuleScript")
		testModule.Source = "return 42"

		local spyRequire = createSpyRequire(true, "Cannot require a non-RobloxScript module from a RobloxScript")

		loader = createModuleLoader({
			require = spyRequire.fn,
			loadmodule = nil, -- FFlag off: loadmodule unavailable
			getSource = function(ms: ModuleScript)
				return ms.Source
			end,
			compile = forceTmpScriptPath,
		})

		expect(function()
			loader.require(testModule)
		end).toThrow("debug.loadmodule is required for this context but is unavailable")
	end)

	test("flips context when error contains RobloxScript (graceful heuristic)", function()
		local testModule = Instance.new("ModuleScript")
		testModule.Source = "return 42"

		-- Inject require that throws a DIFFERENT message, but still contains "RobloxScript".
		local differentMessage = "Some custom RobloxScript restriction error"
		local spyRequire = createSpyRequire(true, differentMessage)
		local fakeLoadmodule = createFakeLoadmodule(88)

		loader = createModuleLoader({
			require = spyRequire.fn,
			loadmodule = fakeLoadmodule.fn,
			getSource = function(ms: ModuleScript)
				return ms.Source
			end,
			compile = forceTmpScriptPath,
		})

		local result = loader.require(testModule)

		-- Should still fall back to loadmodule (heuristic matched "RobloxScript").
		expect(result).toBe(88)
	end)

	test("falls back to native require when source is unreadable", function()
		local testModule = Instance.new("ModuleScript")
		testModule.Source = "return 123"

		local spyRequire = createSpyRequire(false) -- Should NOT error; used for native path.

		loader = createModuleLoader({
			require = spyRequire.fn,
			getSource = function(_: ModuleScript)
				return nil -- Unreadable source
			end,
		})

		local result = loader.require(testModule)

		-- Native require returns the real module.
		expect(result).toBe(123)

		-- Spy should have been called once (native path).
		expect(spyRequire.getCallCount()).toBe(1)
	end)

	describe("preserves high local count modules (React-like)", function()
		test("loads a module with 200+ locals via loadstring double-factory", function()
			local moduleScript = Instance.new("ModuleScript")
			moduleScript.Source = ""

			-- Generate a module with exactly 200 local variables.
			-- This is a regression guard against the 200-local Luau limit that would
			-- have caused a syntax error without the double-factory wrapper.
			-- The double-factory pattern isolates the source locals in a nested function,
			-- so they do not contribute to the outer function's local count.
			for i = 1, 200 do
				moduleScript.Source ..= `local var{i} = {i}\n`
			end
			moduleScript.Source ..= "return { count = 200 }"

			-- This should NOT throw a syntax error about hitting the 200-local limit.
			-- Without the double-factory, Luau would error with "Too many local variables".
			local result = loader.require(moduleScript) :: any

			expect((result :: any).count).toBe(200)
		end)
	end)
end)
