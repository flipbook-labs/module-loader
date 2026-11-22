# ModuleLoader

ModuleLoader requires ModuleScripts without Roblox's `require` cache. Change a module, require it again, and the new code runs without restarting the place. Storyteller and Flipbook use it to reload stories. The [API reference](https://flipbook-labs.github.io/module-loader/api/ModuleLoader) covers every method.

## Install

With Wally:

```toml
[dependencies]
ModuleLoader = "flipbook-labs/module-loader@0.13.0"
```

With Lute, add this to `pkg.luau` and run `lute pkg install --vendor`:

```luau
["module-loader"] = {
	rev = "v0.13.0",
	sourceKind = "github",
	source = "https://github.com/flipbook-labs/module-loader",
},
```

## Use

Require a ModuleScript through a loader instead of `require`:

```luau
local ModuleLoader = require("@pkg/ModuleLoader")

local loader = ModuleLoader.new()
local result = loader:require(game:GetService("ReplicatedStorage").Stories.Button)
```

## Reloading

`loadedModuleChanged` fires when a module loaded through the loader, or any module it requires, has its ancestry or `Source` changed. Clear the loader's cache and require the module again inside the handler:

```luau
local ModuleLoader = require("@pkg/ModuleLoader")

local loader = ModuleLoader.new()
local module = game:GetService("ReplicatedStorage").Stories.Button
local result = loader:require(module)

loader.loadedModuleChanged:Connect(function()
	loader:clear()
	result = loader:require(module)
end)
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT.

Parts of the loader come from [roblox-testservice-watcher](https://github.com/OrbitalOwen/roblox-testservice-watcher) by OrbitalOwen, which is released under the [MIT License](https://github.com/OrbitalOwen/roblox-testservice-watcher/blob/master/LICENSE.md).
