return function()
	local getEnv = require(script.Parent.getEnv)

	it("should return a table", function()
		expect(getEnv()).to.be.a("table")
	end)

	it("should have the correct 'scriipt' global", function()
		local env = getEnv(script.Parent.getEnv)
		expect(env.script).to.equal(script.Parent.getEnv)
	end)
end
