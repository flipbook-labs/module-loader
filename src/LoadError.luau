--[[
	When a module fails to load, the loader usually raises a LoadError. It
	keeps the error's message apart from the traceback the loader adds, so a
	caller can show the message on its own. A module can also raise a table or
	another value of its own, and that value reaches the caller as it was
	raised.

	Converting a LoadError to a string gives its message, then its traceback on
	the next line when it has one. That's the same text `debug.traceback`
	returns for the message, so `tostring` and string interpolation work for
	callers that only want text.
]]

export type LoadError = {
	-- The error the module raised, such as "Module:12: attempt to index nil
	-- with 'Padding'", or the module's syntax error.
	message: string,
	-- Where the error happened, one stack frame per line. Empty when the
	-- error happened before any module ran, such as a syntax error in the
	-- module passed to `require`.
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
