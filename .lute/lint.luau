local FlipbookBatteries = require("@luaupkg/flipbook-batteries")
local path = require("@std/path")
local process = require("@std/process")

local project = require("@repo/project")

local run = FlipbookBatteries.run

local function findLuaFiles(): { path.path }
	local matches: { path.path } = {}

	local function search(filePath: path.pathlike)
		local found = FlipbookBatteries.findWhere(filePath, function(descendantPath)
			return path.extname(descendantPath) == ".lua"
		end)

		for _, file in found do
			table.insert(matches, file)
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
