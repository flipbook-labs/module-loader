return function()
	local createTablePassthrough = require(script.Parent.createTablePassthrough)

	it("should work for the use case of maintaining global variables", function()
		local allGlobals = {}
		local moduleGlobals1 = createTablePassthrough(allGlobals)
		local moduleGlobals2 = createTablePassthrough(allGlobals)

		moduleGlobals1.foo = true
		moduleGlobals2.bar = true

		expect(moduleGlobals1.foo).to.equal(true)
		expect(moduleGlobals1.bar).to.equal(true)
		expect(rawget(moduleGlobals1, "bar")).never.to.be.ok()

		expect(moduleGlobals2.bar).to.equal(true)
		expect(moduleGlobals2.foo).to.equal(true)
		expect(rawget(moduleGlobals2, "foo")).never.to.be.ok()

		expect(allGlobals.foo).to.equal(true)
		expect(allGlobals.bar).to.equal(true)
	end)
end
