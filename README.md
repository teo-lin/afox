# Agent Fleet Orchestration multipleXer (afox)

AFOX is a small shell + tmux toolkit that spawns a fleet of agents with the main goal of implementing Epics

Each agent has a different role, from a different provider, with different permissions, MCPs and tools, all configurable.

We use Beads for issue tracking internally, and Jira externally.

## Example layout

| Role         | Provider (shipped) | Verified alternates       | Description                               | Permissions        | Tools / MCPs                                          |
| ------------ | ------------------ | ------------------------- | ----------------------------------------- | ------------------ | ----------------------------------------------------- |
| ORCHESTRATOR | `claude.opus`    | —                        | Breaks epic down, sequences, delegates    | no code, no writes | `mcp__jira`                                         |
| ARCHITECT    | `claude.fable`   | —                        | Designs interfaces, structure, data flow  | plans only         | `mcp__serena`, `mcp__jira`                        |
| DEVELOPER    | `claude.sonnet`  | —                        | Implements the plan, never self-approves  | writes code        | `mcp__serena`, `mcp__mysql`                       |
| TESTER       | `claude.sonnet`  | `gemini.*`, `devin.*` | Verifies against the running system       | no fixes           | `mcp__browser`, `mcp__cloudwatch`, `mcp__mysql` |
| REVIEWER     | `claude.opus`    | `codex.*`, `devin.*`  | Correctness review, findings to DEVELOPER | no fixes           | `mcp__github`, `mcp__sonarcloud`, `mcp__serena` |

# Why?

- context rot
- no Epic level toolkit exists (you have Gas town for Application level, MultiClaude and tools like it for ticket level)
- no way to orchestrate agents from different providers (e.g Devin + Claude + Copilot + Codex + Goose etc)

## QuickStart

`tmux.conf` — the original. `~/.tmux.conf` is a symlink to it. Edit this file.
`fleet.sh` — spawn 4 role panes (orchestrator / architect / developer / reviewer).
`setup.sh` — installs a `fleet` shell function into your rc. Idempotent.

## Keys

Cmd and Ctrl are swapped globally, so **physical Cmd = true Ctrl**. tmux only sees true Ctrl.

| Action           | Keys                             |
| ---------------- | -------------------------------- |
| split left/right | `Cmd+\` `Cmd+\`              |
| move pane        | `Cmd+\` then arrow             |
| close pane       | type`exit`                     |
| force-kill pane  | `Cmd+\` then `x`, then `y` |
| new window       | `Cmd+\` then `c`             |
| detach           | `Cmd+\` then `d`             |

Mouse is on: click panes and status-bar window names. Hold **Option** to drag-select natively instead of into tmux copy-mode.

## Install

```sh
cp .env.example .env    # optional: FLEET_REPO, CLAUDE_CONFIG_DIR. Quote the values.
./setup.sh              # adds `fleet` to .zshrc / .bash_profile / config.fish
exec $SHELL             # or just open a new pane
```

zsh, bash and fish only. PowerShell is out of scope — tmux has no native Windows build; under WSL this works unchanged.

Aliases and functions from `.zshrc` **do** work in tmux panes: `default-command` is empty, so tmux starts `/bin/zsh` as a login shell. They are missing only when a command string is passed to `new-window`/`split-window`, which tmux runs via `sh -c`.

## Fleet

```sh
fleet                   # current session, auto-detected
fleet '$43'             # explicit session id
```

Idempotent — kills an existing `fleet` window first. Costs ~4x tokens.

Teardown: `tmux kill-window -t '$43:fleet'`

First run prompts to trust the folder in each pane. Accept **one, wait, then the rest** — concurrent writes to `$CLAUDE_CONFIG_DIR/.claude.json` clobber each other. Recorded after that.

## Gotchas (each failed silently)

A dying pane command makes tmux drop the whole window, so `set -e` aborts with no error.

1. `CLAUDE_CONFIG_DIR` must be passed explicitly (set it in `.env`) — tmux runs pane commands via `sh -c`, so the `cc` alias in `.zshrc` does not exist. Bare `claude` reads `~/.claude`: no credentials, no trust.
2. Target sessions by id (`$43`), never name — VSCode names sessions numerically, so `-t 36` parses as *window index* 36 half the time.
3. Pass `-c "$REPO"` to `new-window`/`split-window` — panes otherwise inherit the caller's cwd (wrong tree, fresh trust prompt).
4. Roles go in pane-scoped user options, not pane titles — claude overwrites the title via OSC. `set -p @role X` + `pane-border-format '#{pane_index}: #{@role}'`.
5. `-d` on `new-window`/`split-window` or it steals focus.

## Unverified

- **Peer messaging** (`ListAgents` / `SendMessage` between panes). Returned "No reachable agents" every attempt, but never against a fully-booted session — proves nothing either way. Confirmed fallback: `tmux send-keys -t <target> '<prompt>' Enter` then `tmux capture-pane -p -t <target>`.
- **Prefix delivery.** `Cmd+\` then `x` did nothing; double-tap split untested since `C-\` became the prefix. Bare `C-\` as a root binding did work. If the prefix is not landing, every keyboard shortcut above is dead and the fix is root bindings (`bind -n`) instead of a prefix.
