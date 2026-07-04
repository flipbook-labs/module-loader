local ReplicatedStorage = game:GetService("ReplicatedStorage")

local JestGlobals = require("@pkg/JestGlobals")
local test = JestGlobals.test
local expect = JestGlobals.expect
local describe = JestGlobals.describe

local resolveInstancePath = require("./resolveInstancePath")

describe("@game alias", function()
	test("resolves a descendant path under game", function()
		local moduleScript = Instance.new("ModuleScript")
		moduleScript.Parent = ReplicatedStorage

		expect(resolveInstancePath(moduleScript, "@game/ReplicatedStorage/ModuleScript")).toBe(moduleScript)

		moduleScript:Destroy()
	end)

	test("resolves to game itself when the path is only the alias", function()
		local moduleScript = Instance.new("ModuleScript")

		expect(resolveInstancePath(moduleScript, "@game")).toBe(game)
	end)
end)

describe("@self alias", function()
	test("resolves a child of the module the path is relative to", function()
		local root = Instance.new("ModuleScript")

		local child = Instance.new("ModuleScript")
		child.Parent = root

		expect(resolveInstancePath(root, "@self/ModuleScript")).toBe(child)
	end)

	test("resolves to the module itself when the path is only the alias", function()
		local root = Instance.new("ModuleScript")

		expect(resolveInstancePath(root, "@self")).toBe(root)
	end)

	test("resolves a multi-segment descendant path", function()
		local root = Instance.new("ModuleScript")
		root.Name = "Root"

		local folder = Instance.new("Folder")
		folder.Name = "Nested"
		folder.Parent = root

		local leaf = Instance.new("ModuleScript")
		leaf.Name = "Leaf"
		leaf.Parent = folder

		expect(resolveInstancePath(root, "@self/Nested/Leaf")).toBe(leaf)
	end)
end)

describe("relative ascent", function()
	local root, child1, child2, descendant

	local function buildTree()
		root = Instance.new("ModuleScript")
		root.Name = "Root"

		child1 = Instance.new("ModuleScript")
		child1.Name = "Child1"
		child1.Parent = root

		child2 = Instance.new("ModuleScript")
		child2.Name = "Child2"
		child2.Parent = child1

		descendant = Instance.new("ModuleScript")
		descendant.Name = "Descendant"
		descendant.Parent = child2
	end

	test("a leading ./ ascends one level to the module's parent", function()
		buildTree()
		expect(resolveInstancePath(descendant, "./")).toBe(child2)
	end)

	test("a leading ../ ascends two levels", function()
		buildTree()
		expect(resolveInstancePath(descendant, "../")).toBe(child1)
	end)

	test("each additional ../ after the first ascends one more level", function()
		buildTree()
		expect(resolveInstancePath(descendant, "../../")).toBe(root)
	end)

	test("can descend into a sibling after ascending", function()
		buildTree()
		local sibling = Instance.new("ModuleScript")
		sibling.Name = "Sibling"
		sibling.Parent = child1

		-- ../ lands on child1 (two levels up), then Sibling descends into it.
		expect(resolveInstancePath(descendant, "../Sibling")).toBe(sibling)
	end)
end)

describe("errors", function()
	test("throws naming the unresolved segment when a child is missing", function()
		local moduleScript = Instance.new("ModuleScript")

		expect(function()
			resolveInstancePath(moduleScript, "@self/DoesNotExist")
		end).toThrow("DoesNotExist")
	end)

	test("throws for absolute paths beginning with '/'", function()
		local moduleScript = Instance.new("ModuleScript")

		expect(function()
			resolveInstancePath(moduleScript, "/Foo/Bar")
		end).toThrow("paths beginning with '/' are not supported in sandboxed string requires")
	end)

	test("throws when '..' appears after the beginning of the path", function()
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
end)
