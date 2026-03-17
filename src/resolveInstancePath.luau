local PATH_SEPARATOR = "/"

local function resolveInstancePath(relativeTo: Instance, instancePath: string): Instance
	local prevPathPart: string?

	local function resolvePathPart(current: Instance, pathPart: string): Instance
		-- This block applies to the first part of the path where we need to do
		-- special handling for things like aliases and ascending through
		-- parents
		if current == relativeTo then
			if pathPart == "@game" then
				return game
			elseif pathPart == "@self" then
				return current
			elseif pathPart == "." then
				if not current.Parent then
					error(`could not resolve path (no parent for {current})`)
				end
				return current.Parent
			elseif pathPart == ".." then
				-- Paths beginning with `../` need to go up two parents, then
				-- any subsequent use of `..` will only move up one parent.
				if not (current.Parent and current.Parent.Parent) then
					error(`could not resolve path part "{pathPart}" relative to {current}`)
				end
				return current.Parent.Parent
			end
		end

		if pathPart == ".." then
			-- Usage of `..` in the middle of a path is not supported
			if prevPathPart and prevPathPart ~= pathPart then
				error("paths including '..' after the beginning are not supported in sandboxed string requires")
			end

			if not current.Parent then
				error(`could not resolve path part "{pathPart}" relative to {current}`)
			end
			return current.Parent
		end

		local candidate = current:FindFirstChild(pathPart)
		if not candidate then
			error(`could not resolve an Instance named "{pathPart}" relative to {current}`)
		end
		return candidate
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
		if pathPart == "" and prevPathPart ~= nil then
			continue
		end

		if not prevPathPart and pathPart == "" then
			error("paths beginning with '/' are not supported in sandboxed string requires")
		end

		current = resolvePathPart(current, pathPart)

		prevPathPart = pathPart
	end

	return current
end

return resolveInstancePath
