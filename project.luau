-- All paths are relative to the root of the repo

return {
	SOURCE_PATH = "src",
	BUILD_PATH = "dist",
	PACKAGES_PATH = "Packages",
	LUNE_SCRIPTS_PATH = ".lune",

	SOURCEMAP_PATH = "sourcemap.json",
	DARKLUA_SOURCEMAP_PATH = "sourcemap-darklua.json",

	ROJO_ANALYSIS_PROJECT = "analysis.project.json",
	ROJO_BUILD_PROJECT = "build.project.json",
	ROJO_TESTS_PROJECT = "tests.project.json",

	FOLDERS_TO_LINT = {
		"src",
		".lune",
	},

	ROBLOX_UNIT_TESTING_PLACE_ID = "123506190725771",
	ROBLOX_UNIT_TESTING_UNIVERSE_ID = "6599100156",
}
