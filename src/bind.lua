local function bind(self: table, callback)
	return function(...)
		return callback(self, ...)
	end
end

return bind
