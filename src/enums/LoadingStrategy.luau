export type LoadingStrategy = "Automatic" | "LoadString" | "LoadModule" | "CloneRequire"

local LoadingStrategy = {
	Automatic = "Automatic" :: "Automatic",
	LoadString = "LoadString" :: "LoadString",
	LoadModule = "LoadModule" :: "LoadModule",
	CloneRequire = "CloneRequire" :: "CloneRequire",
}

return LoadingStrategy
