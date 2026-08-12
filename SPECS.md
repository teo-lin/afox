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
| 8 | Stand-down guaranteed | Partial — prompt-only "stand-down line," verified for claude panes only | Platform-enforced idle for every provider | High |
| 9 | Cost monitoring | Not met | Per-session token/spend tracking, budget stop | Medium — cheap, solved pattern exists |
| 10 | Agent↔agent comms | Unverified — `ListAgents` returns "No reachable agents" every attempt | Confirm or replace with a working channel | Medium — blocks spec 11 |
| 11 | Active listening | Not designed — pipeline is strictly sequential by choice | Open research question | Low/stretch — no prior art anywhere |
| 12 | Worktree isolation | Not met, by design — single writer, sequential tickets | No action | — validated design, not a gap |
| 13 | Merge/CI gate | Not met — TESTER/REVIEWER report to ORCHESTRATOR, no auto-merge | Open question | Needs a decision, not an implementation |

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

**8. Stand-down guaranteed — High priority.**
Currently a "stand-down line" appended to non-`system`-style provider prompts
(`providers.yml`), observed to work in two spot checks (codex, devin) but never
proven as a guarantee — it is a request, not an enforcement. No competitor in
the survey solved this either (AWS CAO's role/allowlist enforcement is closest,
but scoped to tools, not to idle-state). This stays afox's own biggest
already-documented risk (see README "Unverified" section) independent of what
competitors do. Fixing it doesn't require copying anyone; it requires either
(a) a provider-side flag that actually blocks first-turn execution, or (b) a
wrapper that holds the prompt until explicitly released.

**9. Cost monitoring — Medium priority, solved pattern available.**
Not implemented. agent-deck (Category B) has the best-in-survey reference:
per-session token tracking, daily price refresh, budget limit with an 80%
warning and a 100% hard stop. Nothing about afox's shape (5 fixed panes, known
providers) makes this hard to add — it's a wrapper around each pane's provider
CLI output, not a redesign. Lowest-effort, highest-certainty item on this list.

**10. Agent↔agent comms — Medium priority, blocks spec 11.**
`ListAgents` / `SendMessage` between panes returns "No reachable agents" on
every attempt logged so far. Confirmed fallback is `tmux send-keys` +
`tmux capture-pane`, which works but is not agent-initiated — a human or a
script drives it. Before investing in spec 11 (active listening), this needs
to be either confirmed working against a fully-booted session, or replaced.
Herdr's socket API (agents subscribe to each other's state-change events) is
the closest working reference pattern found, though it wasn't confirmed to
support a decide-and-resume flow on top.

**11. Active listening — Low priority / stretch, no prior art.**
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

**13. Merge/CI gate — needs a decision, not an implementation.**
Currently no automated gate: TESTER and REVIEWER report findings to
ORCHESTRATOR, and nothing auto-merges. MultiClaude's CI-as-one-way-ratchet and
Composio's autonomous CI-fix loop are the two working references, but both are
PR-per-task tools (Category B-adjacent), not epic-pipeline tools — porting
either pattern changes what "done" means for a ticket in afox's model. Open
question for the user, not a build task: does a ticket's Jira/Beads closure
already imply an equivalent gate outside afox's scope, or does afox need one
of its own?
