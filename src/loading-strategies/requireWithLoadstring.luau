local cleanLoadstringStack = require("@root/cleanLoadstringStack")
local getModuleSource = require("@root/getModuleSource")

local function requireWithLoadstring(moduleScript: ModuleScript)
	local moduleFunction, errorMessage = loadstring(getModuleSource(moduleScript), moduleScript:GetFullName())
	if errorMessage then
		errorMessage = cleanLoadstringStack(errorMessage)
	end

	return moduleFunction, errorMessage
end

return requireWithLoadstring
