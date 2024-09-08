local JestGlobals = require("@pkg/JestGlobals")
local it = JestGlobals.it
local expect = JestGlobals.expect

local bind = require("./bind")

it("should bind 'self' to the given callback", function()
	local module = {
		value = "foo",
		callback = function(self)
			return self.value
		end,
	}

	local callback = bind(module, module.callback)

	expect(callback()).toBe("foo")
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

	expect(getValue()).toBe("foo")
end)
