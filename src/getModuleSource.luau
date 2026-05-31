local ScriptEditorService: ScriptEditorService?
pcall(function()
	ScriptEditorService = game:GetService("ScriptEditorService")
end)

local function getModuleSource(moduleScript: ModuleScript): string?
	if ScriptEditorService then
		local ok, result = pcall(function()
			return ScriptEditorService:GetEditorSource(moduleScript)
		end)
		if ok then
			return result
		end
	end

	local success, result = pcall(function()
		return moduleScript.Source
	end)

	return if success then result else nil
end

return getModuleSource
