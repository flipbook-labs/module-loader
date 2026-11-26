--[[
	When a module fails to load, the loader usually raises a ModuleLoadError. It
	keeps the error's message apart from the traceback the loader adds, so a
	caller can show the message on its own. A module can also raise a table or
	another value of its own, and that value reaches the caller as it was
	raised.

	Converting a ModuleLoadError to a string gives its message, then its
	traceback on the next line when it has one. That's the same text
	`debug.traceback` returns for the message, so `tostring` and string
	interpolation work for callers that only want text.
]]

export type ModuleLoadError = {
	-- The error the module raised, such as "Module:12: attempt to index nil
	-- with 'Padding'", or the module's syntax error.
	message: string,
	-- Where the error happened, one stack frame per line. Empty when the
	-- error happened before any module ran, such as a syntax error in the
	-- module passed to `require`.
	traceback: string,
}

local metatable = {
	__tostring = function(moduleLoadError: ModuleLoadError): string
		if moduleLoadError.traceback == "" then
			return moduleLoadError.message
		end
		return `{moduleLoadError.message}\n{moduleLoadError.traceback}`
	end,
}

-- Every ModuleLoadError this module has made. Keys are weak, so a
-- ModuleLoadError nothing else holds can still be collected.
local moduleLoadErrors: { [unknown]: true } = {}
setmetatable(moduleLoadErrors, { __mode = "k" })

local ModuleLoadError = {}

function ModuleLoadError.new(message: string, traceback: string): ModuleLoadError
	local moduleLoadError: unknown = setmetatable({
		message = message,
		traceback = traceback,
	}, metatable)
	moduleLoadErrors[moduleLoadError] = true
	return moduleLoadError :: ModuleLoadError
end

function ModuleLoadError.is(value: unknown): boolean
	return moduleLoadErrors[value] == true
end

return ModuleLoadError
