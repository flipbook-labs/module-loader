local JestGlobals = require("@pkg/JestGlobals")
local test = JestGlobals.test
local expect = JestGlobals.expect
local describe = JestGlobals.describe

local createModuleRegistry = require("./createModuleRegistry")

local function newModule(name: string?): ModuleScript
	local moduleScript = Instance.new("ModuleScript")
	if name then
		moduleScript.Name = name
	end
	return moduleScript
end

describe("add / getByInstance / getByFullName", function()
	test("stores the exact LoadedModule that was added, keyed by Instance", function()
		local registry = createModuleRegistry()
		local moduleScript = newModule()
		local loadedModule = {} :: any

		registry.add(moduleScript, loadedModule)

		expect(registry.getByInstance(moduleScript)).toBe(loadedModule)
	end)

	test("indexes the same LoadedModule under the Instance's full name", function()
		local registry = createModuleRegistry()
		local moduleScript = newModule()
		local loadedModule = {} :: any

		registry.add(moduleScript, loadedModule)

		-- The value reachable by full name must be the very same table reachable
		-- by Instance, not merely a truthy entry.
		expect(registry.getByFullName(moduleScript:GetFullName())).toBe(loadedModule)
		expect(registry.getByFullName(moduleScript:GetFullName())).toBe(registry.getByInstance(moduleScript))
	end)

	test("overwrites the previous entry when the same Instance is added twice", function()
		local registry = createModuleRegistry()
		local moduleScript = newModule()
		local first = {} :: any
		local second = {} :: any

		registry.add(moduleScript, first)
		registry.add(moduleScript, second)

		expect(registry.getByInstance(moduleScript)).toBe(second)
		expect(registry.getByFullName(moduleScript:GetFullName())).toBe(second)
	end)

	test("returns nil for an Instance that was never added", function()
		local registry = createModuleRegistry()

		expect(registry.getByInstance(newModule())).toBeNil()
	end)

	test("returns nil for a full name that was never added", function()
		local registry = createModuleRegistry()

		expect(registry.getByFullName("Game.Nonexistent")).toBeNil()
	end)
end)

describe("remove", function()
	test("clears both the Instance and full-name indexes for a module", function()
		local registry = createModuleRegistry()
		local moduleScript = newModule()

		registry.add(moduleScript, {} :: any)
		registry.remove(moduleScript)

		expect(registry.getByInstance(moduleScript)).toBeNil()
		expect(registry.getByFullName(moduleScript:GetFullName())).toBeNil()
	end)

	test("leaves other modules intact", function()
		local registry = createModuleRegistry()
		local kept = newModule("Kept")
		local removed = newModule("Removed")
		local keptModule = {} :: any

		registry.add(kept, keptModule)
		registry.add(removed, {} :: any)

		registry.remove(removed)

		expect(registry.getByInstance(kept)).toBe(keptModule)
		expect(registry.getByInstance(removed)).toBeNil()
	end)

	test("is a no-op for a module that was never added", function()
		local registry = createModuleRegistry()

		expect(function()
			registry.remove(newModule())
		end).never.toThrow()
	end)
end)

describe("getAllModules", function()
	test("returns an empty list before anything is added", function()
		local registry = createModuleRegistry()

		expect(registry.getAllModules()).toEqual({})
	end)

	test("returns every added module Instance", function()
		local registry = createModuleRegistry()
		local moduleA = newModule("ModuleA")
		local moduleB = newModule("ModuleB")
		local moduleC = newModule("ModuleC")

		registry.add(moduleA, {} :: any)
		registry.add(moduleB, {} :: any)
		registry.add(moduleC, {} :: any)

		local all = registry.getAllModules()

		expect(#all).toBe(3)
		expect(all).toContain(moduleA)
		expect(all).toContain(moduleB)
		expect(all).toContain(moduleC)
	end)

	test("stops reporting a module once it is removed", function()
		local registry = createModuleRegistry()
		local moduleScript = newModule()

		registry.add(moduleScript, {} :: any)
		registry.remove(moduleScript)

		expect(registry.getAllModules()).never.toContain(moduleScript)
	end)
end)

describe("reset", function()
	test("clears every module from both indexes", function()
		local registry = createModuleRegistry()
		local folder = Instance.new("Folder")

		local modules = {}
		for _, name in { "ModuleA", "ModuleB", "ModuleC" } do
			local moduleScript = newModule(name)
			moduleScript.Parent = folder
			registry.add(moduleScript, {} :: any)
			table.insert(modules, moduleScript)
		end

		registry.reset()

		expect(registry.getAllModules()).toEqual({})
		for _, moduleScript in modules do
			expect(registry.getByInstance(moduleScript)).toBeNil()
			expect(registry.getByFullName(moduleScript:GetFullName())).toBeNil()
		end
	end)
end)
