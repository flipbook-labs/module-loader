local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Jest = require(ReplicatedStorage.Packages.Jest)

local root = ReplicatedStorage.Packages.ModuleLoader

-- selene: allow(global_usage)
_G.__DEV__ = true
-- selene: allow(global_usage)
_G.__ROACT_17_MOCK_SCHEDULER__ = true

local status, result = Jest.runCLI(root, {
	verbose = false,
	ci = false,
}, { root }):awaitStatus()

if status == "Rejected" then
	print(result)
end

return nil
