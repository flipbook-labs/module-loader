@AGENTS.md

# Claude-specific routing

Follow [`AGENTS.md`](AGENTS.md) first. Its "Mandatory first steps" gate (bootstrap, resolve the skills path, read the routing index in full) applies to you before any code, tests, changelog entries, or PR prose, and its subagent rule applies every time you use the Task tool.

The one Claude-specific note: the shared skills live under `<skills>/src/<scope>/<name>/SKILL.md` (the `<skills>` path you resolve in step 2 of the gate), not in `.claude/skills/`, so the Skill tool does not surface them. You route to them yourself by following the gate above.
