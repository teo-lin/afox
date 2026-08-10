# Agent Fleet Orchestration multipleXer (afox)

If bd (Beads) installed, use it for all issue tracking. Run bd ready at the start of work to view top-priority unblocked tasks. |

Roles are data in `roles.yml`; pane order = list order. `provider:` is one
`<name>.<model>` from `providers.yml` — one value, one pane. Two testers on two
providers means two role entries.

Three caveats the table cannot show:

- **Permissions are prompt-enforced.** `tools:` goes verbatim to `--allowedTools`, which
  pre-approves and restricts nothing.
- **`tools:` only reaches claude.** Other providers define no `tools_flag`, so their panes
  get the role brief but no pre-approved MCP list.
- **Only claude takes a system prompt.** Elsewhere the role brief arrives as the first user
  turn — a request, not a persona.

---

## Verification

Nothing here is proven by reading it. Behaviour lives in the tmux server's state, so a claim about
this repo is only real once observed:

```sh
tmux list-windows -a -F '#{session_id}:#{window_index} #{window_name}'
tmux list-panes -t '<sess>:fleet' -F '#{pane_index} #{@role} #{pane_current_command}'
tmux capture-pane -p -t '<sess>:fleet.0' | tail -40
```

Prefer inspecting a real `fleet` window over reasoning about what the script should have done.
`README.md` has an **Unverified** section (peer messaging, prefix delivery) — treat those as open
questions, and move an item out of it only after an actual observation, not an argument.

## Cost

Each pane is a full Claude Code session: a 5-role fleet costs ~5x tokens and real CPU for as long
as it lives. Fleets in other tmux sessions keep running; `fleet.sh` only manages the current
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
