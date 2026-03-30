local ScriptEditorService: ScriptEditorService?
pcall(function()
	ScriptEditorService = game:GetService("ScriptEditorService")
end)

local function setModuleSource(moduleScript: ModuleScript, newSource: string)
	if ScriptEditorService then
		ScriptEditorService:UpdateSourceAsync(moduleScript, function()
			return newSource
		end)
	else
		pcall(function()
			moduleScript.Source = newSource
		end)
	end
end

return setModuleSource
