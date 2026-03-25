export type LoadingStrategy = "Automatic" | "LoadString" | "LoadModule" | "RequireByProxy"

local LoadingStrategy = {
	Automatic = "Automatic" :: "Automatic",
	LoadString = "LoadString" :: "LoadString",
	LoadModule = "LoadModule" :: "LoadModule",
	RequireByProxy = "RequireByProxy" :: "RequireByProxy",
}

return LoadingStrategy
