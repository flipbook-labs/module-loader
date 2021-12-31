local function generateScriptExtension(script)
	if script:IsA("ModuleScript") then
		return ".lua"
	elseif script:IsA("LocalScript") then
		return ".client.lua"
	elseif script:IsA("Script") then
		return ".server.lua"
	end

	return ""
end

local function generateScriptHeader()
	return string.format("--[[%s%s]]\t", script.Name, generateScriptExtension(script))
end

return generateScriptHeader
