local cleanLoadstringStack = require("@root/cleanLoadstringStack")
local types = require("@root/types")

type ModuleChunk = types.ModuleChunk

local function loadString(source: string, chunkName: string): (ModuleChunk?, string?)
	local ok, chunk, errorMessage = pcall(loadstring, source, chunkName)

	if not ok then
		return nil, nil
	end

	if errorMessage then
		errorMessage = cleanLoadstringStack(errorMessage) :: string
	end

	return chunk, errorMessage
end

return loadString
