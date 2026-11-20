# ModuleLoader agent guide

ModuleLoader loads ModuleScripts while bypassing Roblox's `require` cache, which is what lets Flipbook and Storyteller reload stories without restarting. It is written in Luau, built with Lute, and consumed by other repos as a Wally package. This file is the entry point for any agent working in the repo. It routes you to the shared skills library and the repo's own setup.

## Mandatory first steps

Complete every step below before you write any code, tests, changelog entries, or PR prose. This is a gate, and it does not depend on how you classify your task.

1. Install the toolchain and dependencies:

   ```sh
   rokit install && lute run install
   ```

   `rokit install` puts `lute`, `luau-lsp`, `stylua`, and `selene` on PATH. `lute run install` fetches the Loom dependencies into `~/.loom/store`, writes their paths into the aliases in `.config.luau`, and installs the Wally runtime dependencies into `Packages/`. The shared skills library is a dev dependency, so it lands in the store for you to read but is not shipped with the package. Without this step the skills are not on disk.

2. Find the skills folder: it's the `agent-skills` alias in [`.config.luau`](.config.luau). Use that path wherever `<skills>` appears below.

3. Read the routing index at `<skills>/AGENTS.md` in full. Its **Project Skills** section lists every skill with a trigger-rich one-liner, so you know what exists before you start. This read is unconditional.

Deep reads of individual `<skills>/src/<scope>/<name>/SKILL.md` files stay on demand: when a task matches a trigger from the index, read that skill before doing the work it covers. Reading the index up front is what lets those triggers fire.

Reading a skill once does not mean you applied it when you wrote the code hours later. When you take a pass over a change and before you call a task done, follow the `org/review-pass` skill: it maps the diff to the skills that govern each file, has you re-open them at that point, runs the writing-style and code-comments critic passes over what you generated, and catches skill drift to feed back (see below).

## Forward this file to subagents

The Task tool spawns subagents in a fresh context that does not include this guide, so they never see the gate unless you hand it to them. Whenever you delegate to a subagent, you MUST include in its prompt:

1. The mandatory first steps above (the bootstrap command and the index read).
2. The concrete resolved path(s) to the specific `SKILL.md` files relevant to its task.

Never assume a subagent will discover the skills on its own.

## Keeping skills current

Skills are living documents. When your work here contradicts a skill (a renamed symbol, a changed value, a fixed bug it still calls known), fix it in the agent-skills repo with a `.changes/` entry in the same effort. The fix reaches this repo on its next `rev` bump. The `org/review-pass` skill folds this check into closing out a task, so it fires without you having to remember it.

## Repo specifics

- Toolchain is managed with [Rokit](https://github.com/rojo-rbx/rokit). Run `rokit install` once to get `lute`, `luau-lsp`, `stylua`, and `selene` on PATH.
- `lute run --list` shows the available scripts: `install`, `build` (`--channel dev`/`prod`), `lint`, `analyze`, and `test`.
- Tests are `*.spec.luau` files alongside the code they cover. Run the suite with `lute run test`.
- The build copies `src/` to `dist/` and runs [CodeQuality](https://github.com/flipbook-labs/code-quality)'s code mods over the copy with `lute transform`. `convertRequire` rewrites string requires such as `require("@root/types")` into the `require(script...)` paths Roblox runs, using the aliases in `.config.luau` and a Rojo sourcemap of `build.project.json`. Wally publishes from `dist/`. Never edit `dist/` by hand.
- Releases are handled by the [Changewrite](https://github.com/flipbook-labs/changewrite) action. Unreleased entries live as partials in [`.changes/`](.changes) and are assembled into [`CHANGELOG.md`](CHANGELOG.md) at release time. Add a `.changes/` entry for any user-facing change.
