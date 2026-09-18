# Agent Fleet Orchestration multipleXer (afox)

AFOX is a small shell + tmux Harness Multiplexer that spawns a fleet of interconnected agents with the main goal of implementing Epic-level features or even full applications.

Each agent has a different role, from a different provider, with a different harness, with different permissions, MCPs and tools, all configurable.

We use Beads for issue tracking internally, and Jira externally.

## Example layout

| Role         | Provider (shipped)  | Verified alternates          | Description                               | Permissions        | Tools / MCPs                                    |
| ------------ | ------------------- | ---------------------------- | ----------------------------------------- | ------------------ | ----------------------------------------------- |
| ORCHESTRATOR | `claude.opus`       | — (needs peer messaging)     | Breaks epic down, sequences, delegates    | no code, no writes | `mcp__jira`                                     |
| ARCHITECT    | `claude.opus`       | `claude.fable`               | Designs interfaces, structure, data flow  | plans only         | `mcp__serena`, `mcp__jira`                      |
| DEVELOPER    | `claude.sonnet`     | —                            | Implements the plan, never self-approves  | writes code        | `mcp__serena`, `mcp__mysql`                     |
| TESTER       | `devin.swe`         | `gemini.gemini-3.1-pro`      | Verifies against the running system       | no fixes           | `mcp__browser`, `mcp__cloudwatch`, `mcp__mysql` |
| REVIEWER     | `codex.gpt-5.6-sol` | `claude.opus`, `devin.codex` | Correctness review, findings to DEVELOPER | no fixes           | `mcp__github`, `mcp__sonarcloud`, `mcp__serena` |

Registry lives in `providers.yml`; `roles.yml` picks one `<provider>.<model>` per pane.
Providers verified on this machine 2026-08-10:

| Provider | How the brief is delivered (`prompt_style`) | Pane wakes up | `tools:` reaches it |
| -------- | ------------------------------------------- | ------------- | ------------------- |
| `claude` | `--append-system-prompt` (`system`)         | idle          | yes                 |
| `codex`  | positional prompt (`user`)                  | held¹         | no                  |
| `devin`  | prompt after a literal`--` (`user`)         | held¹         | no                  |
| `gemini` | `--prompt-interactive` (`user`)             | held¹         | no                  |

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

| Action             | Keys                       |
| ------------------ | -------------------------- |
| focus a pane       | click it                   |
| move between panes | `Cmd+\` then an arrow      |
| split left/right   | `Cmd+\` `Cmd+\`            |
| force-kill a pane  | `Cmd+\` then `x`, then `y` |
| close a pane       | type`exit`                 |

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
2. Target sessions by id (`$43`), never name — VSCode names sessions numerically, so `-t 36` parses as _window index_ 36 half the time.
3. Pass `-c "$REPO"` to `new-window`/`split-window` — panes otherwise inherit the caller's cwd (wrong tree, fresh trust prompt).
4. Roles go in pane-scoped user options, not pane titles — claude overwrites the title via OSC. `set -p @role X` + `pane-border-format '#{pane_index}: #{@role}'`.
5. `-d` on `new-window`/`split-window` or it steals focus.
6. `roles.mjs` separates fields with US (`0x1f`), not tab — tab is IFS whitespace, so zsh's `read` collapses runs of it. One empty field (a provider with no `tools_flag`) shifted every field after it, and `bin` came back as `devin.swe`.
7. `${tpl%%\{x\}*}${v}${tpl#*\{x\}}` silently _duplicates_ the whole template when `{x}` is absent, so every placeholder substitution is guarded by a presence test.
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

# Agent Fleet Orchestration multipleXer (afox)

If bd (Beads) installed, use it for all issue tracking. Run bd ready at the start of work to view top-priority unblocked tasks. |

Roles are data in `roles.yml`; pane order = list order. `provider:` is one
`<name>.<model>` from `providers.yml` — one value, one pane. Two testers on two
providers means two role entries.

Caveats the table cannot show:

- **Permissions are prompt-enforced.** `tools:` goes verbatim to the provider's `tools_flag`,
  which pre-approves and restricts nothing.
- **`tools:` only reaches claude.** No other provider defines a `tools_flag`, so their panes
  get the role brief and no pre-approved MCP list. `roles.mjs` drops the "tools pre-approved
  for you" sentence for those roles rather than promising a list they will not have.
  Devin's `allowed_tools` is deliberately unwired: it gates tool _visibility_, so a role
  listing only `mcp__jira` would lose Read and Bash and sit there inert.
- **`prompt_style` decides whether a pane wakes up idle.** Only `system` (claude,
  `--append-system-prompt`) installs the brief as a persona. `user` (codex, devin, gemini) has
  no such channel, so the brief is a first user turn — a request, not a persona — and
  `roles.mjs` appends a stand-down line to keep the pane from starting work at spawn.
- **A flag existing is not a channel working.** Devin's `--agent-config` accepts
  `system_instructions` and validates it strictly, then ignores it (v3000.3.27, checked in
  `-p` and in a live pane). Plant a codename and ask for it back before wiring a provider.
- **ORCHESTRATOR must stay on claude.** Peer messaging is a Claude Code feature, so the
  `peer:` text in `roles.yml` is provider-agnostic and `providers.yml` adds the per-provider
  sentence — naming `ListAgents` to codex or devin just invites a hallucinated tool call.

---

## Verification

Nothing here is proven by reading it. Behaviour lives in the tmux server's state, so a claim about
this repo is only real once observed:

```sh
tmux list-windows -a -F '#{session_id}:#{window_index} #{window_name}'
tmux list-panes -t '<sess>:fleet' -F '#{pane_index} #{@role} #{pane_current_command}'
tmux capture-pane -p -t '<sess>:fleet.0' | tail -40
```

`FLEET_DRY_RUN=1 ./fleet.sh` prints each pane's composed command and spawns nothing — use it to
check a provider's flags without paying for N sessions. It proves the command, not the behaviour.

Prefer inspecting a real `fleet` window over reasoning about what the script should have done.
`README.md` has an **Unverified** section (peer messaging, prefix delivery) — treat those as open
questions, and move an item out of it only after an actual observation, not an argument.

## Beads across machines

The Dolt database in `.beads/` is gitignored and never leaves the machine that wrote it.
What travels is `.beads/issues.jsonl`, exported on write (`export.auto`) and tracked in git.
`bd import` is an upsert, so a pull-then-import adds the other machine's tickets and never
replaces the local database.

On a machine that has been away, in this order: `git pull`, then `bd import .beads/issues.jsonl`,
then work. Exporting before importing writes only what this machine knows and drops the other
machine's tickets out of the JSONL — that is the one way to lose a ticket here.

`no-push` is true on purpose: bd does not push Dolt data to the git remote on its own.

## Cost

Each pane is a full agent session: a 5-role fleet costs ~5x tokens and real CPU for as long
as it lives. `user`-style panes (codex, devin, gemini) receive their brief as a real turn, so
they cost tokens the moment they spawn, before you talk to them. Fleets in other tmux sessions keep running; `fleet.sh` only manages the current
session's window and prints the strays it found.

```sh
tmux kill-window -t '$43:fleet'    # teardown
```

## Do Not

- Do not run `fleet` (or `fleet.sh`) unprompted — it spawns N billable agent sessions.
- Do not edit `~/.tmux.conf`; it is a symlink to `tmux.conf` here.
- Do not touch the `# >>> tmux fleet >>>` managed block in the user's rc by hand — `setup.sh` owns it.

## Code Comments

- Comment only what the code cannot say itself: a non-obvious "why", a bug being guarded, a trap.
- 1–2 lines max. No essays, no restating the code, no changelog/ticket narration in code.
- The existing comments in `fleet.sh` are the standard: each one records a silent failure mode.

# Active listening — finding

SPECS.md #11. Ticket afox-3u9.4. Written 2026-09-15 from an observed run, not from an argument.

Active listening was defined as: a peer interrupts a _different_ agent's in-flight task, that
agent decides for itself whether to change course, then resumes — no human relay.

## It is buildable, and for claude panes it already works

No new code was needed. It fell out of the peer channel confirmed in afox-3u9.3.

The run, from the two panes' own session logs:

| Time (UTC) | Pane         | What happened                                                                                                                                                                   |
| ---------- | ------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 07:39:31   | DEVELOPER    | Started a ~60s shell task, said "Command running. Takes ~60s." Turn ended; the task did not.                                                                                    |
| 07:39:4x   | ORCHESTRATOR | `SendMessage` to DEVELOPER: "URGENT PIVOT - stop what you are doing and reply with the word PIVOT immediately."                                                                 |
| 07:39:56   | DEVELOPER    | Took the message while its task was still running. Replied `PIVOT` to ORCHESTRATOR — and refused the rest: "Did **not** stop your tick command — peer cannot cancel your task." |
| 07:40:32   | DEVELOPER    | Went back to the task on its own and reported all 30 lines of its output.                                                                                                       |

Interrupt, decision, resume. No human in the delivery path: `tmux send-keys` carried only the
human instruction into ORCHESTRATOR, never the hop between the two agents.

The decision half is the part worth noticing. DEVELOPER was told by a peer to stop, and it
declined, because it judged the peer had no standing to cancel work its own user had given it.
That is the behaviour the spec wanted, and nothing in afox had to enforce it.

## The one real limit: delivery lands on a turn boundary

A peer message is picked up when the receiving agent's turn ends, not part-way through one.
This did not show in the run above because Claude Code puts long shell work in the background
and ends the turn straight away — so the task was still in flight while the agent was free to
listen. An agent that is actually generating will see the message after that generation ends.

So "interrupt" here means _between turns, while the task is unfinished_, not _mid-sentence_.
For afox's shape — roles that delegate, run tools and report — that is the same thing in
practice. A design that needs to stop a model mid-generation is not buildable on this channel
and is not worth building: the harness owns that boundary, not afox.

## What it does not cover

Claude panes only. Peer messaging is a Claude Code feature, so codex, devin, gemini, copilot
and goose panes never appear in `ListAgents` and cannot be reached this way. A fleet that mixes
providers has active listening for some of its roles and not others. Closing that gap means the
socket API pattern (herdr) referenced in COMPARISON.md — a real build, and nobody has asked for
it yet.

## Recommendation

Nothing to build. Record the behaviour, and spend the effort on the merge gate (afox-99q)
instead, which is what actually sequences the roles today.

# afox vs the field

Desk research, 2026-08-12. Sources are READMEs, vendor blogs, and aggregator
"best of 2026" posts — **not hands-on testing**, except for afox itself (own repo).
Several project names collide across unrelated repos (amux, Conductor, cmux,
Parallel Code); the specific repo used is named where that happened.

## Two product categories

These are genuinely different shapes of tool, not a confidence split:

- **A — Role-differentiated pipelines.** Agents have distinct jobs (architect vs
  tester vs reviewer). This is afox's shape.
- **B — Single-role multiplexers.** N copies of the same kind of agent working N
  tickets in parallel, isolated by worktree. No role differentiation.

## Specs (Columns)

| Code                      | Question                                                                                          |
| ------------------------- | ------------------------------------------------------------------------------------------------- |
| **Score**                 | Sum of ✅(1)/~(0.5) over pipeline columns (A) or infra columns (B). Not comparable across tables. |
| **Multi-agent**           | Can it run more than one agent at once?                                                           |
| **Multi-provider**        | Does one fleet mix agent products (Claude, Codex, Devin, Gemini, local models...)?                |
| **Multi-role**            | Are agents differentiated by*job*, not just N copies of the same role on N tickets?               |
| **Orchestration**         | Does something sequence/delegate/gate the work, or is it a viewer with a human doing that?        |
| **Agent↔agent comms**     | Can one agent message another directly (not human↔agent, not a shared board both poll)?           |
| **Per-role config**       | Can tools/permissions/provider/model be set differently per role in one config?                   |
| **Stand-down guaranteed** | If a role should idle until addressed, is that platform-enforced, or a hopeful prompt?            |
| **Active listening**      | Can a peer interrupt a*different* agent's in-flight task?                                         |
| **Cross-session memory**  | Does state persist across restarts beyond git history itself?                                     |
| **Issue tracking**        | Built-in or integrated task/ticket tracker?                                                       |
| **Cost monitoring**       | Does it track token/API spend?                                                                    |
| **Worktree isolation**    | Does each agent get its own git worktree/branch?                                                  |
| **Merge/CI gate**         | Automated gate (CI, tests) before code lands, or is a human always the gate?                      |
|                           |                                                                                                   |

Legend: ✅ yes · ~ partial/unclear/inferred · ❌ no / not mentioned · ❓ unknown, no data · n/a doesn't apply to this design

---

## Category A — role-differentiated pipelines

Sorted by **pipeline-fit score**: count of ✅ (=1) / ~ (=0.5) across the six
role-pipeline columns (multi-role, orchestration, comms, per-role config,
stand-down, active listening). This is the axis that matters for afox's shape —
not stars, not maturity.

| Tool                                   | Score   | Multi-agent      | Multi-provider                                                                        | Multi-role                                                                        | Orchestration                                                       | Agent↔agent comms                                                                                                         | Per-role config                                                        | Stand-down guaranteed                                             | Active listening                                                                                                              | Cross-session memory                                                   | Issue tracking                                    | Cost monitoring                                                     | Worktree isolation                                        | Merge/CI gate                                                   |
| -------------------------------------- | ------- | ---------------- | ------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------- | ------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------- | ----------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------- | ------------------------------------------------- | ------------------------------------------------------------------- | --------------------------------------------------------- | --------------------------------------------------------------- |
| **AWS CLI Agent Orchestrator (CAO)**   | **4.0** | ✅               | ✅ 9 CLIs (Kiro, Claude, Codex, Antigravity, Hermes, Kimi, Copilot, OpenCode, Cursor) | ~ supervisor + specialists                                                        | ✅ supervisor delegates                                             | ✅ "direct worker interaction, real-time steering" via HTTP API/PTY WebSocket — human↔worker confirmed, worker↔worker not | ✅ "roles, allowlists, provider enforcement"                           | ❓                                                                | ~ real-time steering is human-in-the-loop, not peer-to-peer                                                                   | ✅ persistent memory + "lessons → promoted instructions" loop          | ❓ no dedicated tracker found                     | ❓                                                                  | ✅ session-based isolation                                | ❓                                                              |
| **Agent Teams AI** (777genius)         | **4.0** | ✅               | ✅ "75+ LLM providers", 200+ models                                                   | ✅ teams w/ distinct roles                                                        | ✅ kanban + high-level human commands                               | ✅ explicit: "message each other, and review each other's work"                                                           | ~ per-provider selection, not clearly per-role tool/permission         | ❓                                                                | ~ "review each other's work" implies feedback; timing (mid-task vs after) unconfirmed                                         | ❓                                                                     | ✅ kanban board                                   | ❓                                                                  | ❓                                                        | ❓                                                              |
| **afox** (this repo)                   | **3.5** | ✅ 5 fixed panes | ✅ 6 providers incl. local ollama                                                     | ✅ 5 named roles                                                                  | ✅ ORCHESTRATOR role                                                | ❌ unverified —`ListAgents` returned "No reachable agents" every attempt; fallback is `tmux send-keys`                    | ✅`roles.yml`+`providers.yml`: provider, model, tools, prompt per role | ~ prompt-only ("stand-down line"), verified only for claude panes | ❌ not designed — pipeline is strictly sequential, a blocked stage waits rather than interrupting                             | ✅ Beads (internal) + Jira (external)                                  | ✅ Beads + Jira                                   | ❌                                                                  | ❌ by design — single writer, sequential tickets          | ❌ none — TESTER/REVIEWER report to ORCHESTRATOR, no auto-merge |
| **Microsoft Conductor**                | **3.5** | ✅               | ✅ Copilot SDK + Anthropic Agents SDK                                                 | ✅ agents/prompts/routing all in one YAML                                         | ✅ deterministic — a DAG decides what runs next, no LLM in the loop | ~ "agent-to-agent routing" is real but scripted, not free-form messaging                                                  | ✅ YAML per agent                                                      | n/a — deterministic routing sidesteps the idle-pane problem       | ❌ DAG execution is the opposite of an ad-hoc interrupt                                                                       | ❓                                                                     | ❌                                                | ~ routing burns zero tokens (design win), doesn't track agent spend | ❓                                                        | ~ human-in-the-loop gates, not CI                               |
| **Dinesh7N/multi-agent-orchestration** | **3.5** | ✅               | ✅ Claude, Gemini, Codex                                                              | ✅ structured debate implies distinct stances                                     | ✅                                                                  | ✅ debate/consensus is direct agent-to-agent                                                                              | ❓                                                                     | ❓                                                                | ~ debate-to-consensus is the closest thing found to peer interrupt, but runs as a discrete phase, not a live pause-and-resume | ✅ Postgres-backed state                                               | ❌                                                | ❌                                                                  | ❓                                                        | ❓                                                              |
| **Composio Agent Orchestrator**        | **3.0** | ✅               | ✅ agent-agnostic (Claude, Codex, Aider)                                              | ~ one supervisor role plans+spawns, not a named pipeline                          | ✅                                                                  | ❓                                                                                                                        | ✅ plugin-based: agent-, runtime-, tracker-agnostic                    | n/a                                                               | ~ fixes CI/review comments after the fact, not mid-task                                                                       | ❓                                                                     | ✅ GitHub/Linear                                  | ❓                                                                  | ✅ own worktree+branch+PR per agent                       | ✅ "autonomously handles CI fixes"                              |
| **CLITrigger**                         | **2.5** | ✅               | ✅ Claude, Codex, Gemini                                                              | ✅ architect/developer/reviewer "discussion mode"                                 | ✅                                                                  | ~ agents debate, but*before* implementation starts, not mid-task                                                          | ❓                                                                     | ❓                                                                | ❌ debate is pre-implementation, not an interrupt of running work                                                             | ~ cross-project "Morning Review Queue"                                 | ❓                                                | ❓                                                                  | ✅ parallel git worktrees                                 | ❓                                                              |
| **AgentsRoom**                         | **2.5** | ✅               | ✅ Claude, Cursor, Codex, Gemini, Antigravity                                         | ✅ "13 specialized roles"                                                         | ✅ backlog-driven                                                   | ❓                                                                                                                        | ~                                                                      | ❓                                                                | ❓                                                                                                                            | ❓                                                                     | ✅ backlog                                        | ❓                                                                  | ~ deliberately worktree-free by default, opt-in worktrees | ❓                                                              |
| **MultiClaude** (dlorenc)              | **1.5** | ✅               | ❌ Claude-only                                                                        | ~ supervisor/worker/reviewer exist but it's PR-shaped, not ticket-pipeline-shaped | ✅ supervisor unblocks stuck workers                                | ❓                                                                                                                        | ❓                                                                     | n/a                                                               | ❓                                                                                                                            | ❌ none documented                                                     | ~ one task→one branch→one PR, no ticket hierarchy | ❓                                                                  | ✅ core mechanic, one per worker                          | ✅ core mechanic — CI is the literal "one-way ratchet" gate     |
| **Gas Town** (Yegge)                   | **1.0** | ✅ 20–30 agents  | ✅ Claude, Copilot, Codex, Gemini                                                     | ❓                                                                                | ✅                                                                  | ❓                                                                                                                        | ❓                                                                     | ❓                                                                | ❓ — reviewers call it "not consumer-ready, requires expert supervision"                                                      | ✅ Beads ledger is the whole point — audit-trailed, queryable, durable | ✅ Beads                                          | ❓                                                                  | ❓                                                        | ❓                                                              |

---

## Category B — single-role multiplexers

Multi-role is uniformly ❌ here — that's what makes them Category B, not a
scoring miss. Sorted by **infra score**: memory + issue tracking + cost + worktree

- CI (✅=1, ~=0.5). This is the axis these tools actually compete on.

| Tool                                          | Score                            | Multi-agent   | Multi-provider                                      | Orchestration                                                                                                   | Agent↔agent comms                                                                                                                                        | Cross-session memory                                                          | Issue tracking                                                                     | Cost monitoring                                                                        | Worktree isolation                         | Merge/CI gate                          |
| --------------------------------------------- | -------------------------------- | ------------- | --------------------------------------------------- | --------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------- | ---------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------- | ------------------------------------------ | -------------------------------------- |
| **agent-deck** (asheshgoplani)                | **2.0**                          | ✅            | ✅ Claude, Gemini, OpenCode, Codex                  | ❌                                                                                                              | ❌                                                                                                                                                       | ~ session forking preserves context                                           | ❌                                                                                 | ✅ explicit token tracking, daily price refresh, 80%/100% budget stop — best in survey | ~ worktree-aware                           | ❌                                     |
| **Emdash** (generalaction, YC W26)            | **2.0**                          | ✅            | ✅                                                  | ❌                                                                                                              | ❌                                                                                                                                                       | ❌                                                                            | ✅ imports Linear/GitHub/Jira/GitLab/Asana/Monday/Forgejo/Plain — widest in survey | ❌                                                                                     | ✅                                         | ❌                                     |
| **vibe-kanban** (Bloop, now community)        | **2.0**                          | ✅ 10+ agents | ✅                                                  | ~ kanban stages                                                                                                 | ❌                                                                                                                                                       | ❌                                                                            | ✅ kanban is the tracker                                                           | ❌                                                                                     | ✅                                         | ❌                                     |
| **dmux** (standardagents)                     | **1.5**                          | ✅            | ✅ 11–12 CLIs                                       | ❌                                                                                                              | ❌                                                                                                                                                       | ❌                                                                            | ❌                                                                                 | ❌                                                                                     | ✅ core mechanic                           | ~ pre-merge/post-merge lifecycle hooks |
| **Baton** (mraza007)                          | **1.5**                          | ✅            | ✅                                                  | ~ MCP server lets a running agent spawn a new workspace for a sub-task — self-orchestration, not peer messaging | ❌                                                                                                                                                       | ❌                                                                            | ~ polls GitHub Issues                                                              | ❌                                                                                     | ✅                                         | ❌                                     |
| **CodeAgentSwarm**                            | **1.5**                          | ✅            | ✅                                                  | ~ shared board                                                                                                  | ~ agents poll a shared board via MCP, don't message each other                                                                                           | ~ shared board = context continuity                                           | ✅ shared board                                                                    | ❌                                                                                     | ❓                                         | ❌                                     |
| **agent-of-empires**                          | **1.5**                          | ✅            | ✅ 14+ agents                                       | ~ status detection                                                                                              | ❌                                                                                                                                                       | ~ persists across disconnects (session persistence, not cross-session memory) | ❌                                                                                 | ❌                                                                                     | ✅ + optional Docker sandbox               | ❌                                     |
| **herdr** (ogulcancelik)                      | **0** (comms 1.0, separate axis) | ✅            | ✅ 15+ agents                                       | ~ socket API lets agents spawn sub-agents                                                                       | ✅ socket API: agents read each other's output, subscribe to state-change events — closest thing to real agent↔agent comms found anywhere in this survey | ❌                                                                            | ❌                                                                                 | ❌                                                                                     | ❌                                         | ❌                                     |
| **Claude Squad** (smtg-ai)                    | **1.0**                          | ✅            | ~ Claude, Codex, OpenCode, Amp                      | ❌                                                                                                              | ❌                                                                                                                                                       | ❌                                                                            | ❌                                                                                 | ❌                                                                                     | ✅                                         | ❌                                     |
| **Crystal → Nimbalyst** (stravu)              | **1.0**                          | ✅            | ~ Claude, Codex                                     | ❌                                                                                                              | ❌                                                                                                                                                       | ❌                                                                            | ❌                                                                                 | ❌                                                                                     | ✅                                         | ❌                                     |
| **Superset**                                  | **1.0**                          | ✅ 100+       | ✅ Claude, Codex, Cursor, Gemini, Copilot, OpenCode | ~ "selects best agent for a task"                                                                               | ❌                                                                                                                                                       | ❌                                                                            | ❌                                                                                 | ❌                                                                                     | ✅                                         | ❌                                     |
| **Parallel Code** (johannesjo)                | **1.0**                          | ✅            | ✅ Claude, Codex, Gemini                            | ❌ — "run in parallel, not sequence," explicitly not a pipeline                                                 | ❌                                                                                                                                                       | ❌                                                                            | ❌                                                                                 | ❌                                                                                     | ✅                                         | ❌                                     |
| **Garcon**                                    | **1.0**                          | ✅ 7 agents   | ✅                                                  | ~                                                                                                               | ❌                                                                                                                                                       | ❓                                                                            | ~ Git/PR workflow                                                                  | ❌                                                                                     | ❓                                         | ~ PR workflow                          |
| **Better Agent**                              | **1.0**                          | ✅            | ✅ Claude, Codex, Gemini                            | ✅ "parallel delegation"                                                                                        | ❌                                                                                                                                                       | ✅ "persistent state"                                                         | ❌                                                                                 | ❌                                                                                     | ❓                                         | ❌ — "approval gates" = human approval |
| **cmux** (manaflow-ai)                        | **0.5**                          | ✅            | ✅                                                  | ❌                                                                                                              | ❌ notification badges instead of comms                                                                                                                  | ❌                                                                            | ❌                                                                                 | ❌                                                                                     | ~ "workspaces," not always git worktree    | ❌                                     |
| **amux** — collides across 5+ unrelated repos | **0.5**                          | ✅            | ~                                                   | ❌                                                                                                              | ❌                                                                                                                                                       | ❌                                                                            | ❌                                                                                 | ❌                                                                                     | ~ (andyrewlee's version imports worktrees) | ❌                                     |
| **ntm** (Dicklesworthstone)                   | **0.5**                          | ✅            | ✅ Claude, Codex, Gemini                            | ❌                                                                                                              | ❓                                                                                                                                                       | ~ "automated context rotation"                                                | ❌                                                                                 | ❌                                                                                     | ❓                                         | ❌                                     |

---

## The actual competitive-landscape read

**No tool anywhere — Category A or B — confirmed "active listening" as you
defined it**: a peer interrupting a different agent's _in-flight_ task, that
agent deciding for itself whether to change course, then resuming, with no
human relay. Closest approximations, none matching:

- **herdr** — socket API for agents to read each other's output and subscribe
  to state-change events. Plumbing exists; nobody documents the
  pause-decide-resume pattern running on top of it.
- **Agent Teams AI** — agents "review each other's work," timing vs. task
  completion unconfirmed.
- **CLITrigger / Dinesh7N** — both do inter-agent debate, but as a discrete
  phase _before_ or _between_ implementation steps, not an interrupt of code
  actively being written.
- **AWS CAO** — "real-time steering" is human→agent, not agent→agent.

Every Category A pipeline, afox included, avoids the problem by **never running
the stages that would need to interrupt each other concurrently** — gate
sequentially, and there's nothing in-flight to interrupt. That's a real, cheap
design choice, not an oversight. Building actual active listening would be new
ground, not a catch-up feature.

**Features that exist, but never together:**

- Per-role provider/tool/MCP config (afox, CAO, Composio, Microsoft Conductor)
  never appears alongside real cost monitoring (agent-deck, only in Category B,
  single-role).
- Real agent-to-agent comms (Agent Teams AI, herdr, Dinesh7N) never appears
  alongside a durable external issue tracker (afox's Beads+Jira, Emdash's
  8-tracker breadth, CAO's lesson-memory) in the same tool.
- Nobody combines Category A's role differentiation with Category B's
  worktree-per-agent isolation _and_ a merge/CI gate. MultiClaude has the CI
  gate + worktrees but is single-provider and PR-shaped, not role-pipeline-shaped.

**Cheapest wins available to afox, based on what's proven elsewhere:**

1. Cost monitoring — agent-deck's model (per-session token tracking, budget
   stop at a threshold) is a solved, copyable pattern.
2. A real stand-down guarantee for non-claude panes — nobody has solved this
   either, so it's not a "catch up to X" item, but it's the biggest
   already-known gap in afox's own README.
3. Active listening — no prior art. If built, it would be the first.

**Where afox's current design is already validated, not just untested:**
one-writer/sequential/no-worktree is not a corner-cutting shortcut — Microsoft
Conductor and CAO's supervisor pattern both ship without foregrounding
worktrees either. Worktree-per-agent is a Category B answer to a Category B
problem (N copies of one role, same tree, concurrent writes). afox doesn't have
that problem by construction.

# afox — Functional Specs

Requirements derived from the Specs (Columns) table in `COMPARISON.md`, cross-checked
against afox's current implementation (`roles.yml`, `providers.yml`, `fleet.sh`,
`README.md`) and against what the competitive survey found solved, unsolved, or
validated elsewhere. Twelve specs; `Score` is a derived metric from
`COMPARISON.md`, not an independent requirement, so it is excluded here.

| #   | Spec                  | Current state                                                                       | Target                                        | Priority                              |
| --- | --------------------- | ----------------------------------------------------------------------------------- | --------------------------------------------- | ------------------------------------- |
| 1   | Multi-agent           | Met — 5 fixed tmux panes                                                            | Keep                                          | —                                     |
| 2   | Multi-provider        | Met — 6 providers incl. local ollama                                                | Keep                                          | —                                     |
| 3   | Multi-role            | Met — 5 named roles                                                                 | Keep                                          | —                                     |
| 4   | Orchestration         | Met — ORCHESTRATOR role                                                             | Keep                                          | —                                     |
| 5   | Per-role config       | Met — `roles.yml` + `providers.yml`: provider, model, tools, prompt per role        | Keep                                          | —                                     |
| 6   | Cross-session memory  | Met — Beads (internal) + Jira (external)                                            | Keep                                          | —                                     |
| 7   | Issue tracking        | Met — Beads + Jira                                                                  | Keep                                          | —                                     |
| 8   | Stand-down guaranteed | Met — `hold.sh` keeps user-style panes un-started until addressed                   | Keep                                          | —                                     |
| 9   | Cost monitoring       | Not met                                                                             | Per-session token/spend tracking, budget stop | Medium — cheap, solved pattern exists |
| 10  | Agent↔agent comms     | Met — `ListAgents`/`SendMessage` by role name, claude panes only                    | Keep                                          | —                                     |
| 11  | Active listening      | Researched 2026-09-15 — works already between claude panes, see ACTIVE-LISTENING.md | No build                                      | —                                     |
| 12  | Worktree isolation    | Not met, by design — single writer, sequential tickets                              | No action                                     | — validated design, not a gap         |
| 13  | Merge/CI gate         | Decided 2026-09-15 — afox gets its own gate, local only, no CI                      | Build the cycle below                         | Medium                                |

_(table numbered 1–13; "Merge/CI gate" is #13 because it's listed last in the
source Specs table, not because a #12/#13 split was intended.)_

---

## Met specs — no action

**1. Multi-agent.** 5 fixed tmux panes, one per role. No competitor forced a
rethink here.

**2. Multi-provider.** 6 providers registered in `providers.yml`
(claude, codex, devin, gemini, copilot via opencode, goose/ollama). Wider than
most Category A pipelines found (CLITrigger: 3, Composio: 3 named). Narrower
than Category B multiplexers (dmux: 11–12, AWS CAO: 9) — those tools don't
need per-role differentiation, so adding providers costs them less. Not a gap:
afox's binding of a **local** model (`goose.qwen3:8b`) as a peer role next to a
hosted agent product (Devin) was not found anywhere else in the survey.

**3. Multi-role.** 5 named roles (ORCHESTRATOR, ARCHITECT, DEVELOPER, TESTER,
REVIEWER) in `roles.yml`. Matches the shape of AWS CAO, Agent Teams AI,
Microsoft Conductor, AgentsRoom, CLITrigger — this is the whole Category A
axis and afox scores mid-pack on it (3.5/6) mainly because of specs 10 and 11
below, not because the role model itself is thin.

**4. Orchestration.** ORCHESTRATOR role sequences and gates the other four.
Comparable to every Category A tool; Category B tools (Claude Squad, dmux,
Superset, etc.) don't have this at all — they're viewers, not orchestrators.

**5. Per-role config.** `roles.yml` sets provider + model + tools + prompt per
role; `providers.yml` defines what each provider accepts. This is one of
afox's strongest specs relative to the field — only AWS CAO ("roles, allowlists,
provider enforcement"), Composio (plugin-based, agent/runtime/tracker-agnostic),
and Microsoft Conductor (YAML per agent) match it, and none of those three also
mix a local model into the config the way afox does.

**6/7. Cross-session memory & issue tracking.** Beads internally, Jira
externally. Matches Gas Town's Beads-centric design and beats most
competitors on tracker integration — only Emdash's 8-tracker import list and
Composio's GitHub/Linear support are comparably strong, and neither also runs
a durable internal ledger the way Beads does.

---

## Gaps and open questions — action needed

**8. Stand-down guaranteed — Met 2026-09-14.**
Option (b) of the two below: `fleet.sh` runs every `user`-style pane under
`hold.sh`, which composes the provider command and does not execute it. The
provider process does not exist until the pane is addressed — Enter in the pane,
or `./fleet.sh --release` — so there is no first turn to stand down from, and no
spend before it. The appended stand-down line stays as a second layer for after
release. Option (a), a provider-side flag that blocks first-turn execution, was
not pursued: it would have to be found and proven separately for codex, devin,
gemini, copilot and goose, and devin's `--agent-config` is the standing example
of a flag that validates and then does nothing.

Observed: three consecutive fleet spawns with devin and codex panes held, plus a
probe spawn covering gemini, copilot and goose. In every case the pane ran
`hold.sh`, no provider process existed, and nothing was written. Releasing the
panes started devin and codex, which each answered with one line and stopped.

**9. Cost monitoring — Medium priority, solved pattern available.**
Not implemented. agent-deck (Category B) has the best-in-survey reference:
per-session token tracking, daily price refresh, budget limit with an 80%
warning and a 100% hard stop. Nothing about afox's shape (5 fixed panes, known
providers) makes this hard to add — it's a wrapper around each pane's provider
CLI output, not a redesign. Lowest-effort, highest-certainty item on this list.

**10. Agent↔agent comms — Met 2026-09-15.**
Confirmed against a booted fleet. The earlier "No reachable agents" result was
an addressing failure, not an absent channel: peers were reachable all along,
but under auto-generated session names, so `SendMessage` to a role name could
not resolve. `fleet.sh` now passes `--name <ROLE>` to claude, `ListAgents`
lists peers by role, and `SendMessage` to "DEVELOPER" arrives.

Observed: ORCHESTRATOR called `ListAgents` (DEVELOPER and ARCHITECT listed by
role, with their tmux pane ids), then `SendMessage` to DEVELOPER carrying a
planted codename. DEVELOPER's pane showed `Message from @ORCHESTRATOR` with the
codename, and the codename is in DEVELOPER's own session log. No `tmux send-keys`
in the delivery path.

The limit: peer messaging is a Claude Code feature, so it covers the claude panes
only. Codex, devin, gemini, copilot and goose panes do not appear in `ListAgents`.
Reaching those still means `tmux send-keys` + `capture-pane`, which a human or a
script drives. Spec 11 is therefore unblocked for the claude roles and not for the
others — Herdr's socket API stays the reference if that has to change.

**11. Active listening — researched 2026-09-15, no build needed.**
Full finding in `ACTIVE-LISTENING.md`. Observed end to end between two claude
panes: ORCHESTRATOR messaged DEVELOPER while DEVELOPER's task was still running,
DEVELOPER replied, decided for itself not to abandon the task, and then resumed
and reported it. No new code. The limit is that a message lands on a turn
boundary, not mid-generation, and that the channel reaches claude panes only.

Original framing, kept for context:

Defined as: a peer (TESTER/REVIEWER) interrupts a _different_ agent's in-flight
task (DEVELOPER mid-ticket), that agent decides for itself whether to change
course, then resumes — no human relay. Nothing in the survey does this. Every
Category A pipeline, including afox, currently avoids the problem entirely by
gating sequentially: nothing runs concurrently with what would need
interrupting. This is not a competitive gap to close — it would be new ground.
Depends on spec 10 landing first.

**12. Worktree isolation — no action, validated design.**
Deliberately absent: single writer (DEVELOPER), one ticket at a time,
ORCHESTRATOR gates TESTER/REVIEWER before the next ticket starts. Every tool
that makes worktrees load-bearing (MultiClaude, dmux, Claude Squad, Composio,
Superset, Emdash, Baton, vibe-kanban, Parallel Code, agent-of-empires) is,
without exception, a Category B tool running N copies of one role
concurrently on N tickets — a problem afox doesn't have by construction.
Microsoft Conductor and AWS CAO's supervisor pattern (Category A, like afox)
also don't foreground worktrees. Revisit only if afox's DEVELOPER role is ever
fanned out to run more than one ticket at once.

**13. Merge/CI gate — decided 2026-09-15: afox gets its own gate.**
Ticket closure in Jira/Beads was rejected as the gate. afox enforces its own
cycle, and a Beads ticket closes only at the end of it. Local only — no CI is in
scope for now. MultiClaude's CI-as-one-way-ratchet and Composio's autonomous
CI-fix loop stay out for the same reason they were flagged: both are PR-per-task
tools, and afox's unit of work is a ticket, not a PR.

The gate, as the user specified it:

1. DEVELOPER claims a ticket done. TESTER tests it.
2. All green, and REVIEWER reviews. Not before.
3. REVIEWER flags findings. DEVELOPER decides each one:
   correct and in scope — implement it;
   correct and out of scope — file a new Beads ticket or update the relevant
   existing one;
   incorrect — reject the comment.
4. All comments resolved, and TESTER retests.
5. Tests fail and the code is corrected as a result — a new review cycle starts.
6. More than three such cycles, and the fourth is elevated to ARCHITECT, who
   decides how to settle it.
7. Settled by a normal cycle or by ARCHITECT — the work is done and the Beads
   ticket is closed.

Pane lifecycle, decided at the same time: ORCHESTRATOR tears down and respawns
DEVELOPER, TESTER and REVIEWER for each ticket. ORCHESTRATOR is never closed.
ARCHITECT persists between tickets.

Build tickets: afox-99q (the cycle) and afox-2fc (the pane lifecycle).
