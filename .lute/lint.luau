local FlipbookBatteries = require("@luaupkg/flipbook-batteries@v0.12.0")
local path = require("@std/path")
local process = require("@std/process")

local project = require("@repo/project")

local run = FlipbookBatteries.run

local function findLuaFiles(): { path.Path }
	local matches: { path.Path } = {}

	local function search(filePath: path.Pathlike)
		local found = FlipbookBatteries.findWhere(filePath, function(descendantPath)
			return path.extname(descendantPath) == ".lua"
		end)

		for _, file in found do
			-- FIXME: Without this `{ any }` cast Luau gets upset:
			-- TypeError: None of the overloads for function that accept 2 arguments are compatible.
			-- TypeError: Available overloads: <V>({V}, V) -> (); and <V>({V}, number, V) -> ()
			table.insert(matches :: { any }, file)
		end
	end

	for _, folder in project.FOLDERS_TO_LINT do
		search(folder)
	end

	return matches
end

run("selene", { table.unpack(project.FOLDERS_TO_LINT) })

run("stylua", {
	"--check",
	table.unpack(project.FOLDERS_TO_LINT),
})

local files = findLuaFiles()
if #files > 0 then
	print("[err] the following file(s) are using the '.lua' extension. Please change to '.luau' and try again")
	for _, file in files do
		print(file)
	end
	process.exit(1)
end
