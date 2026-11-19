local FlipbookBatteries = require("@lpm/flipbook-batteries@v0.13.1")
local fs = require("@std/fs")
local json = require("@std/json")
local luau = require("@std/luau")
local path = require("@std/path")
local process = require("@std/process")
local system = require("@std/system")

local project = require("@repo/project")

local run = FlipbookBatteries.run

-- CodeQuality is the org's shared package of Luau lint rules, which `lute lint`
-- runs alongside its own. `lute run install` vendors it into a folder under
-- `.lpm`, and the lockfile maps its key in `pkg.luau` to that folder's name.
local function getCodeQualityRulesPath(): path.Path
	local lockfile = luau.loadModule("pkg.lock.luau")
	local folder: string? = lockfile.devDependencies and lockfile.devDependencies["code-quality"]
	assert(folder, "pkg.lock.luau has no code-quality dev dependency. Run 'lute run install' and try again")
	return path.join(".lpm", folder, "src", "rules")
end

local CODE_QUALITY_RULES_PATH = getCodeQualityRulesPath()

local function findLuaFiles(): { path.Path }
	local matches: { path.Path } = {}

	local function search(filePath: path.Pathlike)
		local found = FlipbookBatteries.findWhere(filePath, function(descendantPath)
			return path.extname(descendantPath) == ".lua"
		end)

		for _, file in found do
			-- FIXME: Without this `{ unknown }` cast Luau gets upset:
			-- TypeError: None of the overloads for function that accept 2 arguments are compatible.
			-- TypeError: Available overloads: <V>({V}, V) -> (); and <V>({V}, number, V) -> ()
			table.insert(matches :: { unknown }, file)
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

if not fs.exists(CODE_QUALITY_RULES_PATH) then
	print(
		`[err] CodeQuality rules not found at {path.format(CODE_QUALITY_RULES_PATH)}. Run 'lute run install' and try again`
	)
	process.exit(1)
end

type LintReport = {
	items: {
		{
			uri: string,
			items: {
				{
					code: string?,
					message: string,
					range: { start: { line: number, character: number } },
				}
			},
		}
	},
}

-- `lute lint` exits cleanly even when a rule throws or a file can't be parsed.
-- It only prints an error and moves on. So the findings go to a JSON file
-- instead of the terminal, and anything `lute lint` still prints counts as a
-- failure. It lints one file at a time because Lute's parallel linting can
-- crash at random (flipbook-labs/code-quality#27). The report's name includes
-- this process's id, so lint runs in other checkouts can't overwrite it.
local reportPath = path.join(system.tmpdir(), `module-loader-lint-{process.pid()}.json`)
local lintResult = process.run({
	"lute",
	"lint",
	"--sequential",
	"--json",
	"--output",
	path.format(reportPath),
	"--rules",
	path.format(CODE_QUALITY_RULES_PATH),
	table.unpack(project.FOLDERS_TO_LINT),
})

local lintOutput = lintResult.stdout .. lintResult.stderr
if not lintResult.ok or lintOutput:find("%S") then
	print("[err] lute lint failed")
	print(lintOutput)
	process.exit(1)
end

local report = json.deserialize(fs.readFileToString(reportPath)) :: LintReport
fs.remove(reportPath)
local findingCount = 0
for _, file in report.items do
	for _, finding in file.items do
		findingCount += 1
		local start = finding.range.start
		print(`{file.uri}:{start.line + 1}:{start.character + 1}: [{finding.code or "lint"}] {finding.message}`)
	end
end

if findingCount > 0 then
	print(`[err] lute lint reported {findingCount} finding(s)`)
	process.exit(1)
end

local files = findLuaFiles()
if #files > 0 then
	print("[err] the following file(s) are using the '.lua' extension. Please change to '.luau' and try again")
	for _, file in files do
		print(file)
	end
	process.exit(1)
end
