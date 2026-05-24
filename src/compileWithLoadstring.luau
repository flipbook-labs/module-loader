local cleanLoadstringStack = require("@root/cleanLoadstringStack")
local types = require("@root/types")

type ModuleFunction = types.ModuleFunction

local function loadString(source: string, chunkName: string): (ModuleFunction?, string?)
	local success, moduleFunction, errorMessage = pcall(loadstring, source, chunkName)
	if not success then
		return nil, nil
	end

	if errorMessage then
		errorMessage = cleanLoadstringStack(errorMessage) :: string
	end

	return moduleFunction :: ModuleFunction?, errorMessage
end

return loadString
