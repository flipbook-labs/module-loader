local ReplicatedStorage = game:GetService("ReplicatedStorage")

local JestGlobals = require("@pkg/JestGlobals")
local test = JestGlobals.test
local expect = JestGlobals.expect

local resolveInstancePath = require("./resolveInstancePath")

test("supports @game alias", function()
	local moduleScript = Instance.new("ModuleScript")
	moduleScript.Parent = ReplicatedStorage

	expect(resolveInstancePath(moduleScript, "@game/ReplicatedStorage/ModuleScript")).toBe(moduleScript)

	moduleScript:Destroy()
end)

test("supports @self alias", function()
	local root = Instance.new("ModuleScript")

	local child = Instance.new("ModuleScript")
	child.Parent = root

	expect(resolveInstancePath(root, "@self/ModuleScript")).toBe(child)
end)

test("supports ascending with ./ and ../", function()
	local root = Instance.new("ModuleScript")
	root.Name = "Root"

	local child1 = Instance.new("ModuleScript")
	child1.Name = "Child1"
	child1.Parent = root

	local child2 = Instance.new("ModuleScript")
	child2.Name = "Child2"
	child2.Parent = child1

	local descendant = Instance.new("ModuleScript")
	descendant.Name = "Descendant"
	descendant.Parent = child2

	expect(resolveInstancePath(descendant, "./")).toBe(child2)
	expect(resolveInstancePath(descendant, "../")).toBe(child1)
	expect(resolveInstancePath(descendant, "../../")).toBe(root)
end)

test("throws if the path doesn't resolve to an instance", function()
	local moduleScript = Instance.new("ModuleScript")

	expect(function()
		resolveInstancePath(moduleScript, "@self/DoesNotExist")
	end).toThrow()
end)

test("throws for absolute paths", function()
	local moduleScript = Instance.new("ModuleScript")

	expect(function()
		resolveInstancePath(moduleScript, "/Foo/Bar")
	end).toThrow("paths beginning with '/' are not supported in sandboxed string requires")
end)

test("throws when including '..' anywhere after the first part of the path", function()
	local root = Instance.new("ModuleScript")

	local child = Instance.new("ModuleScript")
	child.Name = "Child"
	child.Parent = root

	local sibling = Instance.new("ModuleScript")
	sibling.Name = "Sibling"
	sibling.Parent = root

	expect(function()
		resolveInstancePath(root, "@self/Child/../Sibling")
	end).toThrow("paths including '..' after the beginning are not supported in sandboxed string requires")
end)
