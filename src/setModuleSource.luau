local ScriptEditorService: ScriptEditorService?
pcall(function()
	ScriptEditorService = game:GetService("ScriptEditorService")
end)

local function setModuleSource(moduleScript: ModuleScript, newSource: string): boolean
	if ScriptEditorService then
		local ok = pcall(function()
			ScriptEditorService:UpdateSourceAsync(moduleScript, function()
				return newSource
			end)
		end)
		if ok then
			return true
		end
	end

	local success = pcall(function()
		moduleScript.Source = newSource
	end)

	return success
end

return setModuleSource
