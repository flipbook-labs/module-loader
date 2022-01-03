return function()
	local bind = require(script.Parent.bind)

	it("should bind 'self' to the given callback", function()
		local module = {
			value = "foo",
			callback = function(self)
				return self.value
			end,
		}

		local callback = bind(module, module.callback)

		expect(callback()).to.equal("foo")
	end)

	it("should work for the usage example", function()
		local Class = {}
		Class.__index = Class

		function Class.new()
			local self = {}
			self.value = "foo"
			return setmetatable(self, Class)
		end

		function Class:getValue()
			return self.value
		end

		local instance = Class.new()
		local getValue = bind(instance, instance.getValue)

		expect(getValue()).to.equal("foo")
	end)
end
