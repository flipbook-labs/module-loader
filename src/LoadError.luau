--[[
	When a module fails to load, the loader raises a LoadError instead of a
	plain string. It keeps the error's message apart from the traceback the
	loader adds, so a caller can show the message on its own.

	Converting one to a string gives the message followed by the traceback,
	the same text the loader raised before it had LoadErrors. So `tostring`
	and string interpolation keep working for callers that only want text.
]]

export type LoadError = {
	-- The error the module raised, such as "Module:12: attempt to index nil
	-- with 'Padding'", or the module's syntax error.
	message: string,
	-- Where the error happened, one stack frame per line. Empty when the
	-- loader had no stack to add, such as for a syntax error in the module
	-- that was required directly.
	traceback: string,
}

local metatable = {
	__tostring = function(loadError: LoadError): string
		if loadError.traceback == "" then
			return loadError.message
		end
		return `{loadError.message}\n{loadError.traceback}`
	end,
}

-- Every LoadError this module has made. Keys are weak, so a LoadError nothing
-- else holds can still be collected.
local loadErrors: { [unknown]: true } = {}
setmetatable(loadErrors, { __mode = "k" })

local LoadError = {}

function LoadError.new(message: string, traceback: string): LoadError
	local loadError: unknown = setmetatable({
		message = message,
		traceback = traceback,
	}, metatable)
	loadErrors[loadError] = true
	return loadError :: LoadError
end

function LoadError.is(value: unknown): boolean
	return loadErrors[value] == true
end

return LoadError
