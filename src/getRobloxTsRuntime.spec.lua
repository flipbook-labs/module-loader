return function()
	local ReplicatedStorage = game:GetService("ReplicatedStorage")

	local getRobloxTsRuntime = require(script.Parent.getRobloxTsRuntime)

	it("should retrieve the roblox-ts runtime library", function()
		local includes = Instance.new("Folder")
		includes.Name = "rbxts_include"
		includes.Parent = ReplicatedStorage

		local mockRuntime = Instance.new("ModuleScript")
		mockRuntime.Name = "RuntimeLib"
		mockRuntime.Parent = includes

		local runtime = getRobloxTsRuntime()

		includes:Destroy()

		expect(runtime == mockRuntime).to.equal(true)
	end)

	it("should return nil if the runtime can't be found", function()
		local runtime = getRobloxTsRuntime()
		expect(runtime).never.to.be.ok()
	end)
end
