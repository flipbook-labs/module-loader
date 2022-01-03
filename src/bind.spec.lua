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
end
