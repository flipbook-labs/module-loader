"use strict";(self.webpackChunkdocs=self.webpackChunkdocs||[]).push([[42],{29487:e=>{e.exports=JSON.parse('{"functions":[{"name":"bind","desc":"Binds an instance method so that it can be called like a function.\\n\\nUsage:\\n\\n```lua\\nlocal Class = {}\\nClass.__index = Class\\n\\nfunction Class.new()\\n\\tlocal self = {}\\n\\tself.value = \\"foo\\"\\n\\treturn setmetatable(self, Class)\\nend\\n\\nfunction Class:getValue()\\n\\treturn self.value\\nend\\n\\nlocal instance = Class.new()\\nlocal getValue = bind(instance, instance.getValue)\\n\\nprint(getValue()) -- \\"foo\\"\\n```","params":[{"name":"self","desc":"","lua_type":"T"},{"name":"callback","desc":"","lua_type":"(self: T, ...any) -> any"}],"returns":[],"function_type":"static","private":true,"source":{"line":29,"path":"src/bind.lua"}},{"name":"new","desc":"Constructs a new ModuleLoader instance.","params":[],"returns":[],"function_type":"static","source":{"line":31,"path":"src/init.lua"}},{"name":"_getSource","desc":"Gets the Source of a ModuleScript.\\n\\nThis method exists primarily so we can better write unit tests. Attempting\\nto index the Source property from a regular script context throws an error,\\nso this method allows us to safely fallback in tests.","params":[{"name":"module","desc":"","lua_type":"ModuleScript"}],"returns":[{"desc":"","lua_type":"any?\\n"}],"function_type":"method","private":true,"source":{"line":88,"path":"src/init.lua"}},{"name":"_trackChanges","desc":"Tracks the changes to a required module\'s ancestry and `Source`.\\n\\nWhen ancestry or `Source` changes, the `loadedModuleChanged` event is fired.\\nWhen this happens, the user should clear the cache and require the root\\nmodule again to reload.","params":[{"name":"module","desc":"","lua_type":"ModuleScript"}],"returns":[],"function_type":"method","private":true,"source":{"line":118,"path":"src/init.lua"}},{"name":"cache","desc":"Set the cached value for a module before it is loaded.\\n\\nThis is useful is very specific situations. For example, this method is\\nused to cache a copy of Roact so that when a module is loaded with this\\nclass it uses the same table instance.\\n\\n```lua\\nlocal moduleInstance = script.Parent.ModuleScript\\nlocal module = require(moduleInstance)\\n\\nlocal loader = ModuleLoader.new()\\nloader:cache(moduleInstance, module)\\n```","params":[{"name":"module","desc":"","lua_type":"ModuleScript"},{"name":"result","desc":"","lua_type":"any"}],"returns":[],"function_type":"method","source":{"line":146,"path":"src/init.lua"}},{"name":"require","desc":"Require a module with a fresh ModuleScript require cache.\\n\\nThis method is functionally the same as running `require(script.Parent.ModuleScript)`,\\nhowever in this case the module is not cached. As such, if a change occurs\\nto the module you can call this method again to get the latest changes.\\n\\n```lua\\nlocal loader = ModuleLoader.new()\\nlocal module = loader:require(script.Parent.ModuleScript)\\n```","params":[{"name":"module","desc":"","lua_type":"ModuleScript"}],"returns":[],"function_type":"method","source":{"line":169,"path":"src/init.lua"}},{"name":"clear","desc":"Clears out the internal cache.\\n\\nWhile this module bypasses Roblox\'s ModuleScript cache, one is still\\nmaintained internally so that repeated requires to the same module return a\\ncached value.\\n\\nThis method should be called when you need to require a module again. i.e.\\nif the module\'s Source has been changed.\\n\\n```lua\\nlocal loader = ModuleLoader.new()\\nloader:require(script.Parent.ModuleScript)\\n\\n-- Later...\\n\\n-- Clear the cache and require the module again\\nloader:clear()\\nloader:require(script.Parent.ModuleScript)\\n```","params":[],"returns":[],"function_type":"method","source":{"line":237,"path":"src/init.lua"}}],"properties":[{"name":"loadedModuleChanged","desc":"Fired when any ModuleScript required through this class has its ancestry\\nor `Source` property changed. This applies to the ModuleScript passed to\\n`ModuleLoader:require()` and every module that it subsequently requirs.\\n\\nThis event is useful for reloading a module when it or any of it\\ndependencies change.\\n\\n```lua\\nlocal loader = ModuleLoader.new()\\nlocal result = loader:require(module)\\n\\nloader.loadedModuleChanged:Connect(function()\\n\\tloader:clear()\\n\\tresult = loader:require(module)\\nend)\\n```\\n\\n\\t","lua_type":"RBXScriptSignal","source":{"line":60,"path":"src/init.lua"}}],"types":[],"name":"ModuleLoader","desc":"ModuleScript loader that bypasses Roblox\'s require cache.\\n\\nThis class aims to solve a common problem where code needs to be run in\\nStudio, but once a change is made to an already required module the whole\\nplace must be reloaded for the cache to be reset. With this class, the cache\\nis ignored when requiring a module so you are able to load a module, make\\nchanges, and load it again without reloading the whole place.","source":{"line":18,"path":"src/init.lua"}}')}}]);