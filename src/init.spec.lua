return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")

	local Mock = require(script.Parent.Parent.Mock)
	local ModuleLoader = require(script.Parent)

	local mockLoadstring = Mock.new()
	local loader: ModuleLoader.Class
	local mockModuleInstance: ModuleScript
	local mockModule = {}

	beforeEach(function()
		mockLoadstring:mockImplementation(function()
			return function()
				return true
			end
		end)

		mockModuleInstance = Instance.new("ModuleScript")

		loader = ModuleLoader.new()
		loader._loadstring = mockLoadstring
	end)

	afterEach(function()
		mockLoadstring:reset()
	end)

	local function countDict(dict: { [string]: any })
		local count = 0
		for _ in pairs(dict) do
			count += 1
		end
		return count
	end

	describe("_getSource", function()
		-- This test doesn't supply much value. Essentially, the "Source"
		-- property requires elevated permissions, so we need the _getSource
		-- method so that that if tests are being run from within a normal
		-- script context that an error will not be produced.
		it("should return the Source property if it can be indexed", function()
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

	describe("loadedModuleChanged", function()
		it("should fire when a required module has its ancestry changed", function()
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
			local wasFired = false

			mockModuleInstance = Mock.new()

			-- This method needs to be stubbed out to suppress an error
			mockModuleInstance.GetFullName:mockImplementation(function()
				return "Path.To.ModuleScript"
			end)

			-- Need to stub out this event to suppress an error
			mockModuleInstance.AncestryChanged = Instance.new("BindableEvent").Event

			-- Setup mock Changed event since we can't modify the Source
			-- property ourselves
			local sourceChanged = Instance.new("BindableEvent")
			mockModuleInstance.Changed = sourceChanged.Event

			loader.loadedModuleChanged:Connect(function(other: ModuleScript)
				if other == mockModuleInstance then
					wasFired = true
				end
			end)

			-- Require the module so that events get setup
			loader:require(mockModuleInstance)

			-- Trigger the mocked Changed event
			sourceChanged:Fire("Source")

			expect(wasFired).to.equal(true)
		end)
	end)

	describe("cache", function()
		it("should add a module and its result to the cache", function()
			loader:cache(mockModuleInstance, mockModule)

			local cachedModule = loader._cache[mockModuleInstance:GetFullName()]

			expect(cachedModule).to.be.ok()
			expect(cachedModule.result).to.equal(mockModule)
		end)
	end)

	describe("require", function()
		it("should use loadstring to load the module", function()
			loader:require(mockModuleInstance)
			expect(#mockLoadstring.mock.calls).to.equal(1)
		end)

		it("should add the module to the cache", function()
			loader:require(mockModuleInstance)
			expect(loader._cache[mockModuleInstance:GetFullName()]).to.be.ok()
		end)
	end)

	describe("clear", function()
		it("should remove all modules from the cache", function()
			loader:cache(mockModuleInstance, mockModule)

			expect(countDict(loader._cache)).to.equal(1)

			loader:clear()

			expect(countDict(loader._cache)).to.equal(0)
		end)
	end)

	-- For these tests to work, TestEZ must be run from a plugin context so that
	-- loadstring works, along with assigning to the `Source` property of
	-- modules
	describe("consumers", function()
		local modules = Instance.new("Folder") :: Folder & {
			ModuleA: ModuleScript,
			ModuleB: ModuleScript,
			ModuleC: ModuleScript,
		}

		beforeEach(function()
			local moduleA = Instance.new("ModuleScript")
			moduleA.Name = "ModuleA"
			moduleA.Source = [[
				require(script.Parent.ModuleB)

				return "ModuleA"
			]]
			moduleA.Parent = modules

			local moduleB = Instance.new("ModuleScript")
			moduleB.Name = "ModuleB"
			moduleB.Source = [[
				return "ModuleB"
			]]
			moduleB.Parent = modules

			local moduleC = Instance.new("ModuleScript")
			moduleC.Name = "ModuleC"
			moduleC.Source = [[
				return "ModuleC"
			]]
			moduleC.Parent = modules

			modules.Parent = game

			loader._loadstring = loadstring
		end)

		afterEach(function()
			modules:ClearAllChildren()
		end)

		it("should keep track of the consumers for a module", function()
			loader:require(modules.ModuleA)

			expect(loader._cache[modules.ModuleA:GetFullName()]).to.be.ok()

			local cachedModuleB = loader._cache[modules.ModuleB:GetFullName()]

			expect(cachedModuleB).to.be.ok()
			expect(#cachedModuleB.consumers).to.equal(1)
			expect(cachedModuleB.consumers[1]).to.equal(modules.ModuleA:GetFullName())
		end)

		it("should remove all consumers of a changed module from the cache", function()
			loader:require(modules.ModuleA)

			expect(next(loader._cache)).to.be.ok()

			task.defer(function()
				modules.ModuleB.Source = 'return "ModuleB Reloaded"'
			end)
			loader.loadedModuleChanged:Wait()

			expect(next(loader._cache)).never.to.be.ok()
		end)

		it("should not interfere with other cached modules", function()
			loader:require(modules.ModuleA)
			loader:require(modules.ModuleC)

			expect(next(loader._cache)).to.be.ok()

			task.defer(function()
				modules.ModuleB.Source = 'return "ModuleB Reloaded"'
			end)
			loader.loadedModuleChanged:Wait()

			expect(loader._cache[modules.ModuleA:GetFullName()]).never.to.be.ok()
			expect(loader._cache[modules.ModuleB:GetFullName()]).never.to.be.ok()
			expect(loader._cache[modules.ModuleC:GetFullName()]).to.be.ok()
		end)
	end)
end
