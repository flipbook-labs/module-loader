local PATH_SEPARATOR = "/"

local function resolvePathPart(relativeTo: Instance, pathPart: string): Instance
	if pathPart:sub(1, 1) == "/" then
		error(
			"paths beginning with '/' are not supported in sandboxed string requires. use @game as the first part of your path instead",
			2
		)
	end

	if pathPart:sub(1, 1) == "@" then
		if pathPart == "@game" then
			return game
		elseif pathPart == "@self" then
			return relativeTo
		end
	else
		if pathPart == "." then
			if not relativeTo.Parent then
				error(`could not resolve path (no parent for {relativeTo})`, 2)
			end
			return relativeTo.Parent
		elseif pathPart == ".." then
			if not (relativeTo.Parent and relativeTo.Parent.Parent) then
				error(`could not resolve path part "{pathPart}" relative to {relativeTo}`, 2)
			end
			return relativeTo.Parent.Parent
		else
			local candidate = relativeTo:FindFirstChild(pathPart)
			if not candidate then
				error(`could not resolve an Instance named "{pathPart}" relative to {relativeTo}`)
			end
			return candidate
		end
	end

	error(`could not resolve path part "{pathPart}" for {relativeTo}`)
end

local function resolveInstancePath(relativeTo: Instance, instancePath: string): Instance
	local current = relativeTo

	for _, pathPart in instancePath:split(PATH_SEPARATOR) do
		if pathPart == "" then
			break
		end
		current = resolvePathPart(current, pathPart)
	end

	return current
end

return resolveInstancePath
