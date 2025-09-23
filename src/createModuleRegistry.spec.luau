local JestGlobals = require("@pkg/JestGlobals")
local test = JestGlobals.test
local expect = JestGlobals.expect

local createModuleRegistry = require("./createModuleRegistry")

test("adds a module to the registry", function()
	local registry = createModuleRegistry()

	local moduleScript = Instance.new("ModuleScript")
	local mockLoadedModule = {} :: any

	registry.add(moduleScript, mockLoadedModule)

	expect(registry.getByInstance(moduleScript)).toBeDefined()
	expect(registry.getByFullName(moduleScript:GetFullName())).toBeDefined()
end)

test("removes a module from the registry", function()
	local registry = createModuleRegistry()

	local moduleScript = Instance.new("ModuleScript")
	local mockLoadedModule = {} :: any

	registry.add(moduleScript, mockLoadedModule)

	expect(registry.getByInstance(moduleScript)).toBeDefined()
	expect(registry.getByFullName(moduleScript:GetFullName())).toBeDefined()

	registry.remove(moduleScript)

	expect(registry.getByInstance(moduleScript)).toBeUndefined()
	expect(registry.getByFullName(moduleScript:GetFullName())).toBeUndefined()
end)

test("reset the registry", function()
	local registry = createModuleRegistry()

	local folder = Instance.new("Folder")

	for _, name in { "ModuleA", "ModuleB", "ModuleC" } do
		local moduleScript = Instance.new("ModuleScript")
		moduleScript.Name = name
		moduleScript.Parent = folder

		local mockLoadedModule = {} :: any

		registry.add(moduleScript, mockLoadedModule)
	end

	for _, moduleScript in folder:GetChildren() do
		expect(registry.getByInstance(moduleScript :: ModuleScript)).toBeDefined()
		expect(registry.getByFullName(moduleScript:GetFullName())).toBeDefined()
	end

	registry.reset()

	for _, moduleScript in folder:GetChildren() do
		expect(registry.getByInstance(moduleScript :: ModuleScript)).toBeUndefined()
		expect(registry.getByFullName(moduleScript:GetFullName())).toBeUndefined()
	end
end)
