local JestGlobals = require("@pkg/JestGlobals")
local test = JestGlobals.test
local expect = JestGlobals.expect

local createTablePassthrough = require("./createTablePassthrough")

test("works for the use case of maintaining global variables", function()
	local allGlobals = {}
	local moduleGlobals1 = createTablePassthrough(allGlobals)
	local moduleGlobals2 = createTablePassthrough(allGlobals)

	moduleGlobals1.foo = true
	moduleGlobals2.bar = true

	expect(moduleGlobals1.foo).toBe(true)
	expect(moduleGlobals1.bar).toBe(true)
	expect(rawget(moduleGlobals1, "bar")).toBeUndefined()

	expect(moduleGlobals2.bar).toBe(true)
	expect(moduleGlobals2.foo).toBe(true)
	expect(rawget(moduleGlobals2, "foo")).toBeUndefined()

	expect(allGlobals.foo).toBe(true)
	expect(allGlobals.bar).toBe(true)
end)
