return function()
	local getEnv = require(script.Parent.getEnv)

	it("should return a table", function()
		expect(getEnv()).to.be.a("table")
	end)

	it("should have the correct 'script' global", function()
		local env = getEnv(script.Parent.getEnv)
		expect(env.script).to.equal(script.Parent.getEnv)
	end)

	it("should set _G to the 'globals' argument", function()
		local globals = {}
		local env = getEnv(script.Parent.getEnv, globals)

		expect(env._G).to.be.ok()
		expect(env._G).to.equal(globals)
		-- selene: allow(global_usage)
		expect(env._G).never.to.equal(_G)
	end)
end
