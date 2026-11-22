# Contributing

Thanks for working on ModuleLoader. Start by installing the toolchain and the repo's dependencies.

## Setup

Install [Rokit](https://github.com/rojo-rbx/rokit), then run this from the repo root:

```sh
rokit install
lute run install
```

`rokit install` puts `lute`, `luau-lsp`, and `stylua` on your PATH. `lute run install` vendors the Lute dependencies into `.lpm/` and installs the Wally packages into `Packages/`.

## Checks

```sh
lute run build --channel dev
lute run lint
lute run analyze
lute run test
```

`lute run build` copies `src/` to `dist/`, which is what Wally publishes. `lute run test` runs the `*.spec.luau` suite inside Roblox through Open Cloud, so it needs a `ROBLOX_API_KEY` in `.env` or passed with `--apiKey`.

## Changes

Add a file to [`.changes/`](.changes) for each user-facing change. Changewrite assembles those files into `CHANGELOG.md` at release time. See [`.changes/README.md`](.changes/README.md) for the fields.
