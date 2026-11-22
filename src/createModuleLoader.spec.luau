local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ScriptService = game:GetService("ScriptService")

local JestGlobals = require("@pkg/JestGlobals")
local test = JestGlobals.test
local expect = JestGlobals.expect
local describe = JestGlobals.describe
local beforeEach = JestGlobals.beforeEach
local afterEach = JestGlobals.afterEach

local compileWithLoadstring = require("./compileWithLoadstring")
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

local mockModuleSource = {}
local loader: typeof(createModuleLoader())
local moduleRegistry: typeof(loader._getModuleRegistry())
local tree: Instance

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

	test("stops firing after the cache is cleared", function()
		local mockModuleInstance = Instance.new("ModuleScript")
		mockModuleInstance.Source = "return nil"
		mockModuleInstance.Parent = game

		loader.require(mockModuleInstance)

		-- clear() disconnects the change listeners set up during require, so a
		-- later change to a no-longer-tracked module must not fire the signal.
		loader.clear()

		local firedAfterClear = false
		loader.loadedModuleChanged:Connect(function()
			firedAfterClear = true
		end)

		mockModuleInstance.Source = "return true"
		task.wait()

		expect(firedAfterClear).toBe(false)

		mockModuleInstance:Destroy()
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

	test("short-circuits execution so a cached module's source never runs", function()
		local moduleScript = Instance.new("ModuleScript")
		-- If the cache was bypassed, requiring would execute this and throw.
		moduleScript.Source = "error('cached module should not be executed')"

		loader.cache(moduleScript, "cached")

		expect(loader.require(moduleScript)).toBe("cached")
	end)
end)

describe("require", function()
	test("returns the identical cached result on a repeated require of the same module", function()
		local moduleScript = Instance.new("ModuleScript")
		-- A fresh table is allocated each time the source runs, so table
		-- identity across two requires proves the cached value was returned
		-- rather than the source being executed a second time.
		moduleScript.Source = "return {}"

		local first = loader.require(moduleScript)
		local second = loader.require(moduleScript)

		expect(first).toBe(second)
	end)

	test("returns every value a module returns", function()
		local moduleScript = Instance.new("ModuleScript")
		moduleScript.Source = "return 1, 2, 3"

		local a, b, c = loader.require(moduleScript)

		expect(a).toBe(1)
		expect(b).toBe(2)
		expect(c).toBe(3)
	end)

	test("exposes the module itself to its source as the `script` global", function()
		local moduleScript = Instance.new("ModuleScript")
		moduleScript.Source = "return script"

		expect(loader.require(moduleScript)).toBe(moduleScript)
	end)

	test("propagates a runtime error raised while a module loads", function()
		local moduleScript = Instance.new("ModuleScript")
		moduleScript.Source = "error('boom')"

		expect(function()
			loader.require(moduleScript)
		end).toThrow("boom")
	end)

	test("adds one traceback to an error raised by a nested require", function()
		tree = createModuleTest({
			Outer = [[
				require(script.Parent.Middle)
			]],
			Middle = [[
				require(script.Parent.Inner)
			]],
			Inner = [[
				error("boom")
			]],
		})

		local outer = tree:QueryDescendants("#Outer")[1] :: ModuleScript
		local ok, err = pcall(loader.require, outer)

		expect(ok).toBe(false)
		local _, specFrameCount = tostring(err):gsub("createModuleLoader%.spec", "")
		expect(specFrameCount).toBe(1)
	end)

	test("adds a traceback to a nil error raised before any other error", function()
		tree = createModuleTest({
			Outer = [[
				require(script.Parent.Inner)
			]],
			Inner = [[
				error(nil)
			]],
		})

		local outer = tree:QueryDescendants("#Outer")[1] :: ModuleScript
		local ok, err = pcall(loader.require, outer)

		expect(ok).toBe(false)
		expect(tostring(err)).toMatch("createModuleLoader%.spec")
	end)

	test("adds a traceback to an error that another loader already traced", function()
		tree = createModuleTest({
			Failing = [[
				error("boom")
			]],
			Rethrowing = [[
				error(_G.__MODULE_LOADER_SPEC_ERROR, 0)
			]],
		})

		local otherLoader = createModuleLoader()
		local failing = tree:QueryDescendants("#Failing")[1] :: ModuleScript
		local _, otherErr = pcall(otherLoader.require, failing)
		otherLoader.clear()

		-- Modules read the real _G through the loader's proxy globals, so this
		-- hands the first loader's traced error to a module in the second.
		_G.__MODULE_LOADER_SPEC_ERROR = otherErr
		local rethrowing = tree:QueryDescendants("#Rethrowing")[1] :: ModuleScript
		local ok, err = pcall(loader.require, rethrowing)
		_G.__MODULE_LOADER_SPEC_ERROR = nil

		-- If the loaders shared a handler, the second would pass the error
		-- through unchanged. Its own handler keeps the message and adds a trace.
		expect(ok).toBe(false)
		expect(err).never.toBe(otherErr)
		expect(tostring(err):sub(1, #tostring(otherErr))).toBe(otherErr)
	end)

	test("does not cache a module that errored, so a later require can succeed", function()
		local moduleScript = Instance.new("ModuleScript")
		moduleScript.Source = "error('boom')"

		expect(function()
			loader.require(moduleScript)
		end).toThrow("boom")

		-- A failed load must not leave a poisoned (never-loaded) entry behind.
		-- With the source fixed, requiring again re-runs it without a clear().
		moduleScript.Source = "return true"

		expect(loader.require(moduleScript)).toBe(true)
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

			(require :: (moduleScript: ModuleScript) -> unknown)(moduleRequiredNormally)

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

				local result =
					loader.require(moduleScript) :: { getValue: () -> boolean, setValue: (value: boolean) -> () }

				expect(result.getValue()).toBe(true)

				result.setValue(false)

				expect(result.getValue()).toBe(false)

				loader.clear()

				result = loader.require(moduleScript) :: { getValue: () -> boolean, setValue: (value: boolean) -> () }
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
						return "resolved"
					]],
					Folder = {
						Module2 = [[
							-- Leading `../` ascends two levels to the outer
							-- Folder, from which Module3 is a child.
							return require("../Module3")
						]],
					},
				},
				Module1 = [[
					return require("./Folder/Folder/Module2")
				]],
				Consumer = [[
					return require("./Module1")
				]],
			} :: unknown) :: ModuleTestTree)

			local consumer = tree:QueryDescendants("#Consumer")[1] :: ModuleScript

			-- The sentinel threads back through every relative hop, so a
			-- misresolved path would surface as a require error or wrong value.
			expect(loader.require(consumer)).toBe("resolved")
		end)

		test("resolves string requires with the injected resolver", function()
			tree = createModuleTest({
				Consumer = [[
					return require("@anything/Target")
				]],
				Target = [[
					return "target"
				]],
			})

			local consumer = tree:QueryDescendants("#Consumer")[1] :: ModuleScript
			local target = tree:QueryDescendants("#Target")[1] :: ModuleScript

			local resolveCalls: { { relativeTo: Instance, path: string } } = {}
			loader = createModuleLoader({
				compile = compileWithLoadstring,
				require = require :: (moduleScript: ModuleScript) -> unknown,
				loadmodule = nil,
				-- ModuleLoader's own parser can't resolve `@anything`, so the
				-- require only succeeds through this resolver.
				resolveModulePath = function(relativeTo: Instance, path: string): Instance
					table.insert(resolveCalls, { relativeTo = relativeTo, path = path })
					return target
				end,
			})

			expect(loader.require(consumer)).toBe("target")
			expect(resolveCalls).toEqual({ { relativeTo = consumer, path = "@anything/Target" } })
		end)

		-- By default, string requires go through ScriptService:ResolveModulePath
		-- when the engine enables it. It sits behind an engine flag that Open
		-- Cloud Luau Execution leaves off, so these specs only run in Studio
		-- with the flag on.
		local isResolveModulePathEnabled = pcall(function()
			return ScriptService:ResolveModulePath(script, "@self")
		end)

		if isResolveModulePathEnabled then
			test("resolves '..' after the beginning of the path", function()
				tree = createModuleTest(({
					Consumer = [[
						return require("./Child/../Target")
					]],
					Child = {
						Placeholder = "return nil",
					},
					Target = [[
						return "target"
					]],
				} :: unknown) :: ModuleTestTree)

				local consumer = tree:QueryDescendants("#Consumer")[1] :: ModuleScript

				expect(loader.require(consumer)).toBe("target")
			end)

			test("throws when the path resolves to something other than a ModuleScript", function()
				tree = createModuleTest(({
					Consumer = [[
						return require("./Child")
					]],
					Child = {
						Placeholder = "return nil",
					},
				} :: unknown) :: ModuleTestTree)

				local consumer = tree:QueryDescendants("#Consumer")[1] :: ModuleScript

				expect(function()
					loader.require(consumer)
				end).toThrow("unable to resolve module path")
			end)
		end

		-- `.config` aliases resolve only through ScriptService:ResolveModulePath
		-- with engine alias resolution on. Both sit behind engine flags that
		-- Open Cloud Luau Execution leaves off, so this probes a real alias.
		local isConfigAliasEnabled: boolean
		do
			local probe = createModuleTest({
				[".config"] = "return { luau = { aliases = { probe = './Target' } } }",
				Target = "return nil",
				Requirer = "return nil",
			})
			local requirer = probe:QueryDescendants("#Requirer")[1] :: ModuleScript

			isConfigAliasEnabled = pcall(function()
				return ScriptService:ResolveModulePath(requirer, "@probe")
			end)

			probe:Destroy()
		end

		if isConfigAliasEnabled then
			test("supports aliases from a .config module", function()
				tree = createModuleTest(({
					[".config"] = "return { luau = { aliases = { shared = './Shared' } } }",
					Shared = {
						Value = [[
							return "aliased"
						]],
					},
					Consumer = [[
						return require("@shared/Value")
					]],
				} :: unknown) :: ModuleTestTree)

				local consumer = tree:QueryDescendants("#Consumer")[1] :: ModuleScript

				expect(loader.require(consumer)).toBe("aliased")
			end)
		end
	end)
end)

describe("sandbox detection", function()
	-- The generated module has no way to name the real ModuleLoader instance
	-- by path from inside the tree, so an ObjectValue smuggles the reference
	-- in. Requiring it through the loader evaluates the real ModuleLoader
	-- source in the sandbox, the same way a consumer's dependency graph would.
	local function createSandboxCheck(): ModuleScript
		tree = createModuleTest({
			CheckSandbox = [[
				local ModuleLoader = require(script.ModuleLoaderScript.Value)
				return ModuleLoader.isSandboxed()
			]],
		})

		local checkSandbox = tree:QueryDescendants("#CheckSandbox")[1] :: ModuleScript

		local moduleLoaderPointer = Instance.new("ObjectValue")
		moduleLoaderPointer.Name = "ModuleLoaderScript"
		moduleLoaderPointer.Value = script.Parent.ModuleLoader
		moduleLoaderPointer.Parent = checkSandbox

		return checkSandbox
	end

	test("isSandboxed() returns false outside of a loader sandbox", function()
		local ModuleLoader = require("@root/ModuleLoader")

		expect(ModuleLoader.isSandboxed()).toBe(false)
	end)

	test("isSandboxed() returns true inside a loader sandbox", function()
		local checkSandbox = createSandboxCheck()

		expect(loader.require(checkSandbox)).toBe(true)
	end)

	test("isSandboxed() returns true inside a sandbox after the loader is cleared", function()
		local checkSandbox = createSandboxCheck()

		loader.require(checkSandbox)
		loader.clear()

		expect(loader.require(checkSandbox)).toBe(true)
	end)

	test("the sandbox marker exists in _G but is not from the real _G", function()
		tree = createModuleTest({
			ReadMarker = [[
				return _G.__MODULE_LOADER_SANDBOX__
			]],
		})

		local readMarker = tree:QueryDescendants("#ReadMarker")[1] :: ModuleScript
		local markerInSandbox = loader.require(readMarker)

		-- The marker should exist in the sandbox
		expect(markerInSandbox).toBeDefined()

		-- But it should NOT exist in the real _G
		expect(_G.__MODULE_LOADER_SANDBOX__).toBeUndefined()
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

describe("RobloxScript security", function()
	local NON_ROBLOXSCRIPT_REQUIRE_ERROR = "Cannot require a non-RobloxScript module from a RobloxScript"

	-- Open Cloud Luau Execution doesn't run at RobloxScript security, so these
	-- tests stand in for the engine calls that behave differently there:
	-- loadstring is unavailable, requiring a created ModuleScript is rejected,
	-- and `debug.loadmodule` compiles the module instead.
	local function compileWithoutLoadstring(_source: string, _chunkName: string)
		return nil, nil
	end

	local requireCallCount = 0

	local function rejectRequire(_moduleScript: ModuleScript): unknown
		requireCallCount += 1
		error(NON_ROBLOXSCRIPT_REQUIRE_ERROR, 2)
	end

	beforeEach(function()
		requireCallCount = 0
	end)

	test("loads a module with debug.loadmodule when requiring it is rejected", function()
		tree = createModuleTest({
			Module = "return script.Name",
		})

		loader = createModuleLoader({
			compile = compileWithoutLoadstring,
			require = rejectRequire,
			loadmodule = function(_moduleScript)
				return function()
					return script.Name
				end
			end,
		})

		local module = tree:QueryDescendants("#Module")[1] :: ModuleScript

		expect(loader.require(module)).toBe("Module")
	end)

	test("resolves requires inside a debug.loadmodule chunk through the loader", function()
		tree = createModuleTest({
			Helper = "return {}",
			Story = "return require(script.Parent.Helper)",
		})

		local chunks: { [string]: () -> ...unknown } = {
			Helper = function()
				return {}
			end,
			Story = function()
				-- The cast keeps the type checker from resolving `Helper`
				-- next to this spec. At runtime both globals belong to the
				-- Story module.
				return (require :: (moduleScript: Instance) -> unknown)(script.Parent.Helper)
			end,
		}

		loader = createModuleLoader({
			compile = compileWithoutLoadstring,
			require = rejectRequire,
			loadmodule = function(moduleScript)
				return chunks[moduleScript.Name]
			end,
		})

		local helper = tree:QueryDescendants("#Helper")[1] :: ModuleScript
		local story = tree:QueryDescendants("#Story")[1] :: ModuleScript

		expect(loader.require(story)).toBe(loader.require(helper))
	end)

	test("stops trying to require modules once requiring has been rejected", function()
		tree = createModuleTest({
			ModuleA = "return 'A'",
			ModuleB = "return 'B'",
		})

		loader = createModuleLoader({
			compile = compileWithoutLoadstring,
			require = rejectRequire,
			loadmodule = function(moduleScript)
				return function()
					return moduleScript.Name
				end
			end,
		})

		loader.require(tree:QueryDescendants("#ModuleA")[1] :: ModuleScript)
		loader.require(tree:QueryDescendants("#ModuleB")[1] :: ModuleScript)

		expect(requireCallCount).toBe(1)
	end)

	test("runs debug.loadmodule cleanup functions when cleared", function()
		tree = createModuleTest({
			ModuleA = "return 'A'",
			ModuleB = "return 'B'",
		})

		local cleanupCount = 0

		loader = createModuleLoader({
			compile = compileWithoutLoadstring,
			require = rejectRequire,
			loadmodule = function(moduleScript)
				return function()
					return moduleScript.Name
				end, nil, function()
					cleanupCount += 1
				end
			end,
		})

		loader.require(tree:QueryDescendants("#ModuleA")[1] :: ModuleScript)
		loader.require(tree:QueryDescendants("#ModuleB")[1] :: ModuleScript)
		loader.clear()

		expect(cleanupCount).toBe(2)
	end)

	test("throws the debug.loadmodule error when a module fails to compile", function()
		tree = createModuleTest({
			Module = "return",
		})

		loader = createModuleLoader({
			compile = compileWithoutLoadstring,
			require = rejectRequire,
			loadmodule = function(_moduleScript)
				return nil, "Module:1: Expected expression"
			end,
		})

		local module = tree:QueryDescendants("#Module")[1] :: ModuleScript

		expect(function()
			loader.require(module)
		end).toThrow("Expected expression")
	end)

	test("throws the require error when debug.loadmodule is unavailable", function()
		tree = createModuleTest({
			Module = "return nil",
		})

		loader = createModuleLoader({
			compile = compileWithoutLoadstring,
			require = rejectRequire,
			loadmodule = nil,
		})

		local module = tree:QueryDescendants("#Module")[1] :: ModuleScript

		expect(function()
			loader.require(module)
		end).toThrow(NON_ROBLOXSCRIPT_REQUIRE_ERROR)
	end)

	test("throws the require error when debug.loadmodule isn't allowed in this context", function()
		tree = createModuleTest({
			Module = "return nil",
		})

		loader = createModuleLoader({
			compile = compileWithoutLoadstring,
			require = rejectRequire,
			loadmodule = function(_moduleScript)
				error("debug.loadmodule is not available at this security level")
			end,
		})

		local module = tree:QueryDescendants("#Module")[1] :: ModuleScript

		expect(function()
			loader.require(module)
		end).toThrow(NON_ROBLOXSCRIPT_REQUIRE_ERROR)
	end)

	test("does not use debug.loadmodule for other require errors", function()
		tree = createModuleTest({
			Module = "return nil",
		})

		local loadmoduleCallCount = 0

		loader = createModuleLoader({
			compile = compileWithoutLoadstring,
			require = function(_moduleScript)
				error("Module code did not return exactly one value")
			end,
			loadmodule = function(_moduleScript)
				loadmoduleCallCount += 1
				return function()
					return nil
				end
			end,
		})

		local module = tree:QueryDescendants("#Module")[1] :: ModuleScript

		expect(function()
			loader.require(module)
		end).toThrow("Module code did not return exactly one value")
		expect(loadmoduleCallCount).toBe(0)
	end)
end)

describe("roblox-ts", function()
	local rbxtsInclude: Folder
	local mockRuntime: ModuleScript

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
