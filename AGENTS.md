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
  Devin's `allowed_tools` is deliberately unwired: it gates tool *visibility*, so a role
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
