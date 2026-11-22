local JestGlobals = require("@pkg/JestGlobals")
local test = JestGlobals.test
local expect = JestGlobals.expect

local bind = require("./bind")

test("calls the function with the bound self followed by the arguments", function()
	local receiver = {}
	local calls: { { self: {}, a: number, b: string } } = {}

	local bound = bind(function(self: {}, a: number, b: string)
		table.insert(calls, { self = self, a = a, b = b })
	end, receiver)

	bound(1, "two")

	expect(#calls).toBe(1)
	expect(calls[1].self).toBe(receiver)
	expect(calls[1].a).toBe(1)
	expect(calls[1].b).toBe("two")
end)

test("returns every value the function returns", function()
	local bound = bind(function(_self: {}, a: number)
		return a, a + 1, a + 2
	end, {})

	local first, second, third = bound(1)

	expect(first).toBe(1)
	expect(second).toBe(2)
	expect(third).toBe(3)
end)
