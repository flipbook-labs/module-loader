local baseEnv = getfenv()

local function getEnv(scriptRelativeTo: LuaSourceContainer?, globals: { [any]: any }?)
	local newEnv = {}

	setmetatable(newEnv, {
		__index = function(_, key)
			if key ~= "plugin" then
				return baseEnv[key]
			else
				return nil
			end
		end,
	})

	newEnv._G = globals
	newEnv.script = scriptRelativeTo

	local realDebug = debug

	newEnv.debug = setmetatable({
		traceback = function(message)
			-- Block traces to prevent overly verbose TestEZ output
			return message or ""
		end,
	}, { __index = realDebug })

	return newEnv
end

return getEnv
