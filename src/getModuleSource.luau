local function getModuleSource(moduleScript: ModuleScript): string
	-- TODO: Also try ScriptEditorService
	local success, result = pcall(function()
		return moduleScript.Source
	end)

	return if success then result else ""
end

return getModuleSource
