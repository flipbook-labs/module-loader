local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Jest = (require :: any)(ReplicatedStorage.Packages.Jest)

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

if status ~= "Resolved" or result.results.numFailedTestSuites > 0 or result.results.numFailedTests > 0 then
	error(1)
end

return nil
