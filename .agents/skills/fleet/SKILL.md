---
name: fleet
description: /fleet status - inspect running fleet windows and panes /fleet spawn - build the fleet window for a session /fleet msg <ROLE> <text> - send a prompt to one pane /fleet kill - tear down a fleet window /fleet doctor - diagnose a fleet that came up wrong. Use when operating, inspecting or debugging the tmux agent fleet.
allowed-tools:
  - read
  - grep
  - exec
---

# Fleet Operations

`fleet.sh` builds a tmux window named `fleet` with one Claude Code pane per role in `roles.yml`.
This skill is how you drive and inspect it. All state lives in the tmux server — read it, never
infer it.

## Cost Gate

Every pane is a full billable Claude Code session. **Never spawn a fleet unless the user asked
for it in this turn.** Inspecting, messaging and killing are free; spawning is not.

## Status

```sh
tmux list-windows -a -F '#{session_id}:#{window_index} #{window_name}'                     # find fleets
tmux list-panes -t '<sess>:fleet' -F '#{pane_index} #{@role} #{pane_current_command} #{pane_pid}'
tmux capture-pane -p -t '<sess>:fleet.0' | tail -40                                        # what a pane is doing
```

`@role` is a pane-scoped user option, not the pane title — claude overwrites titles via OSC, so
`#{pane_title}` is useless for identifying a role.

## Spawn

```sh
fleet                 # current session, auto-detected
fleet '$43'           # explicit session id
fleet '$43' /path/to/repo
```

Idempotent: it kills the existing `fleet` window in that session first. Two constraints that
produce confusing failures:

- **Session ids (`$43`), never names.** VSCode names sessions numerically, so `-t 36` is parsed as
  window index 36 about half the time.
- On first run each pane prompts to trust the folder. **Accept one, wait for it to settle, then the
  rest** — concurrent writes to `$CLAUDE_CONFIG_DIR/.claude.json` clobber each other. Recorded
  after that.

## Message A Pane

Peer messaging via `ListAgents` / `SendMessage` is unverified (see README). The confirmed path is
tmux itself:

```sh
tmux send-keys -t '<sess>:fleet.<idx>' '<prompt>' Enter
tmux capture-pane -p -t '<sess>:fleet.<idx>' | tail -40      # read the reply
```

Resolve `<idx>` from `@role` via the `list-panes` command above; pane order follows `roles.yml`
order but do not hardcode it.

## Teardown

```sh
tmux kill-window -t '$43:fleet'
```

`fleet.sh` only manages the session it was called in. Fleets in other sessions keep burning tokens
and CPU — the script prints strays it finds; kill them explicitly.

## Doctor

Symptom → cause, in the order they actually occur:

| Symptom                                     | Cause                                                                         |
| ------------------------------------------- | ----------------------------------------------------------------------------- |
| Window vanishes immediately, no error        | A pane command died. tmux drops the whole window; `set -e` aborts silently.    |
| Panes ask to log in / re-trust every time    | `CLAUDE_CONFIG_DIR` not reaching the pane — `sh -c` never loads `.zshrc`.      |
| Panes open in the wrong directory            | `-c "$REPO"` missing, so panes inherited the caller's cwd.                     |
| Pane borders show no role                    | `@role` option or `pane-border-format` not set on the window.                  |
| `fleet` command not found                    | `setup.sh` not run, or rc not re-sourced (`exec $SHELL`).                      |
| Keyboard shortcuts dead                      | Prefix `C-\` not landing; fall back to root bindings (`bind -n`). Unverified.  |
| Role has no roles.yml entry but pane exists  | Stale window from a previous `roles.yml`; re-run `fleet`.                      |

Before reporting a cause, confirm it against the live server (`list-panes`, `capture-pane`,
`tmux show-options -p -t <pane>`). A plausible explanation is not a diagnosis.

## Rules

- Do not spawn, kill or send keys to panes in sessions the user did not name.
- Do not edit `roles.yml` while diagnosing a running fleet; finish the diagnosis, then change data.
- Report the command you ran and its raw output, not a summary of what it implies.
