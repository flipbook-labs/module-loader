return function()
	local ModuleLoader = require(script.Parent)

	local loader: ModuleLoader.Class
	local mockModuleSource = {}

	beforeEach(function()
		loader = ModuleLoader.new()
	end)

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
	local function createModuleTest(tree: ModuleTestTree, parent: Instance?)
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
				expect(source).to.be.ok()
			else
				expect(source).to.never.be.ok()
			end
		end)
	end)

	describe("_trackChanges", function()
		it("should create a Janitor instance if it doesn't exist", function()
			local mockModuleInstance = Instance.new("ModuleScript")

			expect(loader._janitors[mockModuleInstance.Name]).never.to.be.ok()

			loader:_trackChanges(mockModuleInstance)

			expect(loader._janitors[mockModuleInstance.Name]).to.be.ok()
		end)

		it("should reuse the same Janitor instance for future calls", function()
			local mockModuleInstance = Instance.new("ModuleScript")

			loader:_trackChanges(mockModuleInstance)

			local janitor = loader._janitors[mockModuleInstance.Name]

			loader:_trackChanges(mockModuleInstance)

			expect(loader._janitors[mockModuleInstance.Name]).to.equal(janitor)
		end)
	end)

	describe("loadedModuleChanged", function()
		it("should fire when a required module has its ancestry changed", function()
			local mockModuleInstance = Instance.new("ModuleScript")

			local wasFired = false

			-- Parent the ModuleScript somewhere in the DataModel so we can
			-- listen for AncestryChanged.
			mockModuleInstance.Parent = script

			loader.loadedModuleChanged:Connect(function(other: ModuleScript)
				if other == mockModuleInstance then
					wasFired = true
				end
			end)

			-- Require the module so that events get setup
			loader:require(mockModuleInstance)

			-- Trigger AncestryChanged to fire
			mockModuleInstance.Parent = nil

			expect(wasFired).to.equal(true)
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

			expect(wasFired).to.equal(true)
		end)
	end)

	describe("cache", function()
		it("should add a module and its result to the cache", function()
			local mockModuleInstance = Instance.new("ModuleScript")

			loader:cache(mockModuleInstance, mockModuleSource)

			local cachedModule = loader._cache[mockModuleInstance:GetFullName()]

			expect(cachedModule).to.be.ok()
			expect(cachedModule.result).to.equal(mockModuleSource)
		end)
	end)

	describe("require", function()
		it("should add the module to the cache", function()
			local mockModuleInstance = Instance.new("ModuleScript")

			loader:require(mockModuleInstance)
			expect(loader._cache[mockModuleInstance:GetFullName()]).to.be.ok()
		end)

		it("should return cached results", function()
			local tree = createModuleTest({
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

			expect(sharedModuleFromConsumer1).to.equal(sharedModuleFromConsumer2)
		end)

		it("should add the calling script as a consumer", function()
			local tree = createModuleTest({
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

			expect(cachedModule).to.be.ok()
			expect(cachedModule.consumers[tree.Consumer:GetFullName()]).to.be.ok()
		end)

		it("should update consumers when requiring a cached module from a different script", function()
			local tree = createModuleTest({
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

			expect(cachedModule.consumers[tree.Consumer1:GetFullName()]).to.be.ok()
			expect(cachedModule.consumers[tree.Consumer2:GetFullName()]).never.to.be.ok()

			loader:require(tree.Consumer2)

			expect(cachedModule.consumers[tree.Consumer1:GetFullName()]).to.be.ok()
			expect(cachedModule.consumers[tree.Consumer2:GetFullName()]).to.be.ok()
		end)

		it("should keep track of _G between modules", function()
			local tree = createModuleTest({
				WriteGlobal = [[
					_G.foo = true
					return nil
				]],
				ReadGlobal = [[
					return _G.foo
				]],
			})

			loader:require(tree.WriteGlobal)

			expect(loader._globals.foo).to.equal(true)

			local result = loader:require(tree.ReadGlobal)

			expect(result).to.equal(true)
		end)

		it("should keep track of _G in nested requires", function()
			local tree = createModuleTest({
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

			expect(result).to.equal(true)

			loader:clear()

			expect(loader._globals.foo).never.to.be.ok()
		end)
	end)

	describe("clear", function()
		it("should remove all modules from the cache", function()
			local mockModuleInstance = Instance.new("ModuleScript")

			loader:cache(mockModuleInstance, mockModuleSource)

			expect(countDict(loader._cache)).to.equal(1)

			loader:clear()

			expect(countDict(loader._cache)).to.equal(0)
		end)

		it("should reset globals", function()
			local globals = loader._globals

			loader:clear()

			expect(loader._globals).never.to.equal(globals)
		end)
	end)

	-- For these tests to work, TestEZ must be run from a plugin context so that
	-- loadstring works, along with assigning to the `Source` property of
	-- modules
	describe("consumers", function()
		local tree = createModuleTest({
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

		it("should keep track of the consumers for a module", function()
			loader:require(tree.ModuleA)

			expect(loader._cache[tree.ModuleA:GetFullName()]).to.be.ok()

			local cachedModuleB = loader._cache[tree.ModuleB:GetFullName()]

			expect(cachedModuleB).to.be.ok()
			expect(countDict(cachedModuleB.consumers)).to.equal(1)
			expect(cachedModuleB.consumers[tree.ModuleA:GetFullName()]).to.be.ok()
		end)

		it("should remove all consumers of a changed module from the cache", function()
			loader:require(tree.ModuleA)

			local hasItems = next(loader._cache) ~= nil
			expect(hasItems).to.equal(true)

			task.defer(function()
				tree.ModuleB.Source = 'return "ModuleB Reloaded"'
			end)
			loader.loadedModuleChanged:Wait()

			hasItems = next(loader._cache) ~= nil
			expect(hasItems).to.equal(false)
		end)

		it("should not interfere with other cached modules", function()
			loader:require(tree.ModuleA)
			loader:require(tree.ModuleC)

			local hasItems = next(loader._cache) ~= nil
			expect(hasItems).to.equal(true)

			task.defer(function()
				tree.ModuleB.Source = 'return "ModuleB Reloaded"'
			end)
			loader.loadedModuleChanged:Wait()

			expect(loader._cache[tree.ModuleA:GetFullName()]).never.to.be.ok()
			expect(loader._cache[tree.ModuleB:GetFullName()]).never.to.be.ok()
			expect(loader._cache[tree.ModuleC:GetFullName()]).to.be.ok()
		end)
	end)
end
