return function()
	local Mock = require(script.Parent.Parent.Mock)
	local ModuleLoader = require(script.Parent)

	local MOCK_MODULE = script.Parent.Mocks.module

	local loader: ModuleLoader.Class

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
				return MOCK_MODULE.Source
			end)

			local source = loader:_getSource(MOCK_MODULE)

			if canIndex then
				expect(source).to.be.ok()
			else
				expect(source).to.never.be.ok()
			end
		end)
	end)

	describe("require", function()
		FOCUS()

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
			loader:require(MOCK_MODULE)
			expect(#mockLoadstring.mock.calls).to.equal(1)
		end)

		it("should add the module to the cache", function()
			loader:require(MOCK_MODULE)
			expect(loader._cache[MOCK_MODULE]).to.be.ok()
		end)
	end)
end
