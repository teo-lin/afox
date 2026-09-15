# Agent Fleet Orchestration multipleXer (afox)

AFOX is a small shell + tmux toolkit that spawns a fleet of agents with the main goal of implementing Epics

Each agent has a different role, from a different provider, with different permissions, MCPs and tools, all configurable.

We use Beads for issue tracking internally, and Jira externally.

## Example layout

| Role         | Provider (shipped) | Verified alternates       | Description                               | Permissions        | Tools / MCPs                                          |
| ------------ | ------------------ | ------------------------- | ----------------------------------------- | ------------------ | ----------------------------------------------------- |
| ORCHESTRATOR | `claude.opus`         | — (needs peer messaging)       | Breaks epic down, sequences, delegates    | no code, no writes | `mcp__jira`                                     |
| ARCHITECT    | `claude.opus`         | `claude.fable`                 | Designs interfaces, structure, data flow  | plans only         | `mcp__serena`, `mcp__jira`                      |
| DEVELOPER    | `claude.sonnet`       | —                              | Implements the plan, never self-approves  | writes code        | `mcp__serena`, `mcp__mysql`                     |
| TESTER       | `devin.swe`           | `gemini.gemini-3.1-pro`        | Verifies against the running system       | no fixes           | `mcp__browser`, `mcp__cloudwatch`, `mcp__mysql` |
| REVIEWER     | `codex.gpt-5.6-sol`   | `claude.opus`, `devin.codex`   | Correctness review, findings to DEVELOPER | no fixes           | `mcp__github`, `mcp__sonarcloud`, `mcp__serena` |

Registry lives in `providers.yml`; `roles.yml` picks one `<provider>.<model>` per pane.
Providers verified on this machine 2026-08-10:

| Provider | How the brief is delivered (`prompt_style`) | Pane wakes up    | `tools:` reaches it |
| -------- | ------------------------------------------- | ---------------- | ------------------- |
| `claude` | `--append-system-prompt` (`system`)         | idle             | yes                 |
| `codex`  | positional prompt (`user`)                  | held¹            | no                  |
| `devin`  | prompt after a literal `--` (`user`)        | held¹            | no                  |
| `gemini` | `--prompt-interactive` (`user`)             | held¹            | no                  |

¹ Only claude has a system-prompt channel. Everywhere else the brief lands as a
first user turn, which reads as "do this now". `roles.mjs` still appends a stand-down
line, but a line is a request — so `fleet.sh` runs those panes under `hold.sh`, which
composes the command and does not start the provider until the pane is addressed.
Observed 2026-09-14 across three consecutive spawns, plus one probe spawn covering
gemini, copilot and goose: no provider process, no file write, no spend. Press Enter
in the pane, or `./fleet.sh --release`, to start it.

Devin's `--agent-config` looks like the right channel and is deliberately unused:
the file parses (unknown fields rejected, `system_instructions` must be an array)
but a codename planted in it was ignored in `-p` and in a live pane both, on
v3000.3.27. Verify a flag does something before wiring a provider to it.

Check what a change actually produces without paying for N sessions:

```sh
FLEET_DRY_RUN=1 ./fleet.sh    # prints each pane's composed command, spawns nothing
```

# Why?

- context rot
- no Epic level toolkit exists (you have Gas town for Application level, MultiClaude and tools like it for ticket level)
- no way to orchestrate agents from different providers (e.g Devin + Claude + Copilot + Codex + Goose etc)

`copilot` has no standalone CLI here, so it is not in the registry. `opencode` is
installed but its only credential is a `GITHUB_TOKEN`, which makes its model ids
account-dependent — add it yourself with `-m provider/model` and `prompt_style: user`.

## QuickStart

`tmux.conf` — the original. `~/.tmux.conf` is a symlink to it. Edit this file.
`fleet.sh` — spawn one pane per role in `roles.yml`.
`hold.sh` — runs in place of a `user`-style provider until the pane is addressed.
`board.mjs` — prints the Beads ticket list as markdown checkboxes; ORCHESTRATOR shows it in its own thread.
`setup.sh` — installs a `fleet` shell function into your rc. Idempotent.

## Keys

Every row below was pressed on a live `fleet` window on 2026-09-14 and did what it says.
Rows that were never pressed are not listed — tmux's own defaults still work, they are
just not claims this README makes.

The prefix is `C-\`. On a machine where Cmd and Ctrl are swapped globally, the key that
sends it is the one labelled **Cmd** — tmux sees true Ctrl either way.

| Action             | Keys                        |
| ------------------ | --------------------------- |
| focus a pane       | click it                    |
| move between panes | `Cmd+\` then an arrow       |
| split left/right   | `Cmd+\` `Cmd+\`             |
| force-kill a pane  | `Cmd+\` then `x`, then `y` |
| close a pane       | type `exit`                 |

Mouse is on, so clicking a pane focuses it — and dragging goes to tmux, not to the
terminal. Neither **Option**-drag nor **Shift**-drag got a native selection back in the
terminal this was tested in, so with the mouse on, copying text means tmux's copy mode.
`tmux set -g mouse off` trades click-to-focus back for normal selection.

## Install

```sh
cp .env.example .env    # optional: CLAUDE_CONFIG_DIR. Quote the values.
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
6. `roles.mjs` separates fields with US (`0x1f`), not tab — tab is IFS whitespace, so zsh's `read` collapses runs of it. One empty field (a provider with no `tools_flag`) shifted every field after it, and `bin` came back as `devin.swe`.
7. `${tpl%%\{x\}*}${v}${tpl#*\{x\}}` silently *duplicates* the whole template when `{x}` is absent, so every placeholder substitution is guarded by a presence test.
8. Every provider gates first use behind its own trust prompt, and they are not the same. Observed: codex asks to trust the directory **and then** to trust 4 changed hooks — two prompts before the pane is usable. Budget for that on a fresh `repo`.

## Peer messaging

Works, between claude panes, 2026-09-15. `ListAgents` lists each peer under the role
name, because `fleet.sh` passes `--name <ROLE>`; `SendMessage` then addresses a peer by
that role name and the message arrives in the other pane. Observed: ORCHESTRATOR sent
DEVELOPER a planted codename, DEVELOPER's pane showed `Message from @ORCHESTRATOR` with
it, and the codename appears in DEVELOPER's own session log. Agent-initiated — no
`tmux send-keys` in the delivery path.

Without `--name` the peers are still reachable but carry auto-generated session names, so
`SendMessage` to "DEVELOPER" fails with "No agent named 'DEVELOPER' is reachable". That,
not an absent channel, is what the old "No reachable agents" result was.

It reaches claude panes only. Peer messaging is a Claude Code feature, so codex, devin,
gemini, copilot and goose panes do not appear in `ListAgents` and cannot be addressed
this way. For those, the fallback is still `tmux send-keys -t <target> '<prompt>' Enter`
then `tmux capture-pane -p -t <target>`, which a human or a script drives.
