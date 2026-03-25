local constants = require("@root/constants")
local requireWithLoadstring = require("@root/loading-strategies/requireWithLoadstring")

local function requireWithCloning(moduleScript: ModuleScript): ((() -> ())?, string?)
	local moduleFunction: (() -> ())?
	local errorMessage: string?

	local clone = moduleScript:Clone()
	clone:AddTag(constants.MODULE_LOCK_TAG)
	clone.Archivable = false

	-- We could have also applied the tag to `moduleScript` first and then
	-- cloned it, but let's keep it explicit.
	moduleScript:AddTag(constants.MODULE_LOCK_TAG)

	-- We wrap the module source in an anonymous function so requiring the
	-- clone returns a runnable function with a function environment we can
	-- manipulate if needed.
	--
	-- We also include `local _;` so injected code preserves line numbers.
	-- It may also have some other benefits but we're largely dealing with
	-- incantations from the old tomes here so we'll take what we can get
	clone.Source = "return function() local _;" .. moduleScript.Source .. "\nend"
	clone.Parent, moduleScript.Parent = moduleScript.Parent, clone.Parent

	local ok, err = pcall(function()
		-- Casting to `any` so require will accept the clone as a valid module path
		moduleFunction = (require :: any)(clone)
		return nil
	end)

	clone.Parent, moduleScript.Parent = moduleScript.Parent, clone.Parent
	clone:Destroy()
	moduleScript:RemoveTag(constants.MODULE_LOCK_TAG)

	if not ok then
		local _, syntaxErrorMessage = requireWithLoadstring(moduleScript)

		if syntaxErrorMessage then
			errorMessage = syntaxErrorMessage
		else
			errorMessage = err
		end

		return nil, errorMessage
	end

	if moduleFunction then
		return moduleFunction, nil
	end

	return nil, nil
end

return requireWithCloning
