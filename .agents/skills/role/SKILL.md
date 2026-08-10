---
name: role
description: /role add <NAME> - add a fleet role /role edit <NAME> - retune an existing role prompt or tools /role remove <NAME> - drop a role /role review - audit roles.yml for overlap, gaps and prompt bloat. Use when changing which agents the fleet spawns or what they own.
allowed-tools:
  - read
  - grep
  - edit
  - exec
---

# Fleet Roles

Roles are **data** in `roles.yml`. `fleet.sh` spawns one pane per entry in list order, so adding or
removing a role needs no code change. Reach for `fleet.sh` only when the *mechanism* changes
(new per-role flag, different layout), never to add a role.

## Entry Shape

```yaml
  - name: REVIEWER
    provider: claude.opus
    tools: mcp__github, mcp__sonarcloud, mcp__serena
    prompt: |
      You own correctness review. One line per finding, most severe first, and
      message DEVELOPER with them directly.
      Do not fix code yourself. Say plainly when a diff is clean.
```

`roles.mjs` parses exactly this shape — top-level scalars, `peer: |`, and a `roles:` list of
`name` / `provider` / `tools` / `prompt: |`. Anchors, nested maps and inline lists are **not**
supported in `roles.yml` and parse to garbage without an error. New syntax means editing
`roles.mjs` too.

## Provider

`provider: <name>.<model>` — **one value, one pane**. `<name>` is a key in `providers.yml`,
`<model>` one of that provider's `models`. Omit the model to take the provider's first; omit
`provider:` entirely to inherit the top-level default in `roles.yml`. Want three testers on three
providers? Write three role entries.

Both halves are validated before the window is built, and a bad value names the valid ones:

```
roles.yml: role ARCHITECT wants claude.turbo; allowed models: opus, sonnet, fable, haiku
roles.yml: role ARCHITECT wants provider "ollama"; providers.yml has: claude, codex, gemini, devin, copilot
```

Adding a provider is a `providers.yml` key (`bin`, `models`, `cmd`, optional `tools_flag`), not a
code change. Two consequences worth stating before switching a role off claude:

- `tools:` is claude-only — no other provider defines a `tools_flag`, so its pane gets the role
  brief with no pre-approved MCP list.
- Only claude has a system-prompt flag. Elsewhere the brief lands as the first user turn.

`fleet.sh` runs `command -v` on every provider `bin` before touching tmux — a missing CLI is a
clean error rather than a pane that dies and takes the whole window with it.

## Prompt Standard

Three sentences is usually enough. A role prompt says only what distinguishes this role from the
others:

1. **What it owns** — the one thing it is accountable for.
2. **What it must not do** — the adjacent work that belongs to a peer.
3. **Who it hands to** — the next role in the chain.

Never restate tool descriptions, `AGENTS.md`, or `.agents/skills` content: every pane already loads
those, so duplicating them costs tokens in every session and drifts out of date. The shared
`peer:` block is appended to every role — do not repeat peer-messaging instructions per role.

Anti-patterns, all of which have to be paid for on every turn of every pane:

- Restating the repo's stack, conventions or file layout.
- Generic quality exhortations ("write clean code", "be thorough").
- Long checklists — if a workflow is long, it belongs in a skill, not a role prompt.
- Two roles whose prompts overlap: they will duplicate work and disagree.

## Tools

`tools:` is comma-separated and passed verbatim to `claude --allowedTools`. It **pre-approves**;
it does not restrict — an unlisted tool still works, it just prompts. So:

- List what the role uses constantly (its MCP servers, its command-level grants like
  `Bash(pnpm run lint:*)`).
- Do not list a tool as a way to "assign" capability, and do not omit one hoping to fence a role
  in — the prompt is the only real boundary.
- Names must be real permission names. A typo is silent: it grants nothing and warns nothing.

## Verify A Change

`roles.yml` is only correct once the parser agrees:

```sh
node roles.mjs roles.yml           # tab-separated CFG/ROLE lines, one ROLE per role
```

Each `ROLE` line has 8 tab-separated fields: `ROLE / name / prompt / tools / cmd / tools_flag /
bin / provider.model`. Check the role count, that the prompt is there, and that `cmd` resolved to
the CLI you expected with `{model}` filled in ( `{prompt}` and `{tools}` stay — `fleet.sh` fills
those, shell-quoted). Then re-run `fleet` (only if the user asked) and confirm pane count and `@role` labels:

```sh
tmux list-panes -t '<sess>:fleet' -F '#{pane_index} #{@role}'
```

## Rules

- Change `roles.yml`, not `fleet.sh`, to add/remove/retune a role.
- Run `node roles.mjs roles.yml` after every edit — a parse failure is otherwise invisible.
- Do not re-run `fleet` to "test" a change unless the user asked; each run spawns N billable sessions.
- `repo:` and `config_dir:` point at another tree and the user's Claude config. Do not change them
  as a side effect of a role edit.
