local PATH_SEPARATOR = "/"

local function resolveInstancePath(relativeTo: Instance, instancePath: string): Instance
	local prevPathPart: string?

	local function resolvePathPart(current: Instance, pathPart: string): Instance
		if pathPart:sub(1, 1) == "/" then
			error(
				"paths beginning with '/' are not supported in sandboxed string requires. use @game as the first part of your path instead"
			)
		end

		if pathPart:sub(1, 1) == "@" then
			if pathPart == "@game" then
				return game
			elseif pathPart == "@self" then
				return current
			end
		else
			if pathPart == "." then
				if not current.Parent then
					error(`could not resolve path (no parent for {current})`)
				end
				return current.Parent
			elseif pathPart == ".." then
				if not (current.Parent and current.Parent.Parent) then
					error(`could not resolve path part "{pathPart}" relative to {current}`)
				end
				return current.Parent.Parent
			else
				local candidate = current:FindFirstChild(pathPart)
				if not candidate then
					error(`could not resolve an Instance named "{pathPart}" relative to {current}`)
				end
				return candidate
			end
		end

		error(`could not resolve path part "{pathPart}" for {relativeTo}`)
	end

	local current = relativeTo

	for _, pathPart in instancePath:split(PATH_SEPARATOR) do
		-- This handles cases where splitting up the path results in empty
		-- strings. For example, `./` splits to `{ ".", "" }` and the latter is
		-- not actually important, so we just skip those ones.
		--
		-- Similar happens if the path has more than one separator, i.e.
		-- `@self/Foo//Bar`, which would become `{ "@self", "Foo", "", "Bar" }`.
		-- We just pretend that empty string doesn't exist
		if pathPart == "" and prevPathPart then
			continue
		end

		if not prevPathPart and pathPart == "" then
			error("paths beginning with '/' are not supported in sandboxed string requires")
		end

		if prevPathPart and prevPathPart ~= ".." and pathPart == ".." then
			error("paths including '..' after the beginning are not supported in sandboxed string requires")
		end

		current = resolvePathPart(current, pathPart)

		prevPathPart = pathPart
	end

	return current
end

return resolveInstancePath
