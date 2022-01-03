return function()
	local Mock = require(script.Parent.Parent.Mock)
	local ModuleLoader = require(script.Parent)

	local mockModuleInstance = script.Parent.Mocks.module
	local mockModule = require(mockModuleInstance)

	local loader: ModuleLoader.Class

	local function countDict(dict: { [string]: any })
		local count = 0
		for _ in pairs(dict) do
			count += 1
		end
		return count
	end

	beforeEach(function()
		loader = ModuleLoader.new()
	end)

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

	describe("cache", function()
		beforeEach(function()
			loader = ModuleLoader.new()
		end)

		it("should add a module and its source to the cache", function()
			loader:cache(mockModuleInstance, mockModule)

			local cachedModule = loader._cache[mockModuleInstance]

			expect(cachedModule).to.be.ok()
			expect(cachedModule[2]).to.equal(mockModule)
		end)
	end)

	describe("require", function()
		local mockLoadstring = Mock.new()

		beforeEach(function()
			mockLoadstring:mockImplementation(function()
				return function()
					return true
				end
			end)

			loader._loadstring = mockLoadstring
		end)

		afterEach(function()
			mockLoadstring:reset()
			loader:clear()
		end)

		it("should use loadstring to load the module", function()
			loader:require(mockModuleInstance)
			expect(#mockLoadstring.mock.calls).to.equal(1)
		end)

		it("should add the module to the cache", function()
			loader:require(mockModuleInstance)
			expect(loader._cache[mockModuleInstance]).to.be.ok()
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
end
