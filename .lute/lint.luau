local FlipbookBatteries = require("@luaupkg/flipbook-batteries")
local fs = require("@std/fs")
local path = require("@std/path")
local process = require("@std/process")

local project = require("@repo/project")

local run = FlipbookBatteries.run

local function findLuaFiles()
	local matches = {}

	local function search(filePath: string)
		for _, file in fs.listdirectory(filePath) do
			local childPath = path.join(filePath, file)

			if fs.type(childPath) == "dir" then
				search(childPath)
			else
				if path.extname(childPath) == ".lua" then
					table.insert(matches, childPath)
				end
			end
		end
	end

	for _, folder in project.FOLDERS_TO_LINT do
		search(folder)
	end

	return matches
end

run("selene", project.FOLDERS_TO_LINT)

run("stylua", {
	"--check",
	table.unpack(project.FOLDERS_TO_LINT),
})

local files = findLuaFiles()
if #files > 0 then
	print("[err] the following file(s) are using the '.lua' extension. Please change to '.luau' and try again")
	print(`{table.concat(files, "\n")}`)
	process.exit(1)
end
