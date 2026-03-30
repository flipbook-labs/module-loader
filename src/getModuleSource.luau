local ScriptEditorService: ScriptEditorService?
pcall(function()
	ScriptEditorService = game:GetService("ScriptEditorService")
end)

local function getModuleSource(moduleScript: ModuleScript): string
	if ScriptEditorService then
		return ScriptEditorService:GetEditorSource(moduleScript)
	end

	local success, result = pcall(function()
		return moduleScript.Source
	end)

	return if success then result else ""
end

return getModuleSource
