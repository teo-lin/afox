# afox — Functional Specs

Requirements derived from the Specs (Columns) table in `COMPARISON.md`, cross-checked
against afox's current implementation (`roles.yml`, `providers.yml`, `fleet.sh`,
`README.md`) and against what the competitive survey found solved, unsolved, or
validated elsewhere. Twelve specs; `Score` is a derived metric from
`COMPARISON.md`, not an independent requirement, so it is excluded here.

| # | Spec | Current state | Target | Priority |
|---|---|---|---|---|
| 1 | Multi-agent | Met — 5 fixed tmux panes | Keep | — |
| 2 | Multi-provider | Met — 6 providers incl. local ollama | Keep | — |
| 3 | Multi-role | Met — 5 named roles | Keep | — |
| 4 | Orchestration | Met — ORCHESTRATOR role | Keep | — |
| 5 | Per-role config | Met — `roles.yml` + `providers.yml`: provider, model, tools, prompt per role | Keep | — |
| 6 | Cross-session memory | Met — Beads (internal) + Jira (external) | Keep | — |
| 7 | Issue tracking | Met — Beads + Jira | Keep | — |
| 8 | Stand-down guaranteed | Met — `hold.sh` keeps user-style panes un-started until addressed | Keep | — |
| 9 | Cost monitoring | Not met | Per-session token/spend tracking, budget stop | Medium — cheap, solved pattern exists |
| 10 | Agent↔agent comms | Met — `ListAgents`/`SendMessage` by role name, claude panes only | Keep | — |
| 11 | Active listening | Researched 2026-09-15 — works already between claude panes, see ACTIVE-LISTENING.md | No build | — |
| 12 | Worktree isolation | Not met, by design — single writer, sequential tickets | No action | — validated design, not a gap |
| 13 | Merge/CI gate | Decided 2026-09-15 — afox gets its own gate, local only, no CI | Build the cycle below | Medium |

*(table numbered 1–13; "Merge/CI gate" is #13 because it's listed last in the
source Specs table, not because a #12/#13 split was intended.)*

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

Defined as: a peer (TESTER/REVIEWER) interrupts a *different* agent's in-flight
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
