# Work order: close the open afox tickets, one at a time

You are working in the `afox` repository (`/Users/teolin/_/afox`). Read `AGENTS.md` before you
touch anything; it is the repo's own rule sheet and it overrides any habit you bring with you.

Your job is to close the open tickets in the Beads tracker, in the order given below, one at a
time. Do not batch them. Do not start a ticket before the previous one is closed or explicitly
parked with a written reason.

## The tracker is the contract

`bd` (Beads) is the source of truth, not this file.

```sh
bd ready              # unblocked work, top priority first
bd show <id>          # read this before every ticket, without exception
bd update <id> --claim
bd close <id> --reason "<what was observed, not what was written>"
```

Every ticket carries an **acceptance criteria** field. That field, and only that field, decides
whether the ticket is done. Do not invent, soften, widen or reinterpret it. If a criterion turns
out to be wrong or impossible, say so and stop — changing the bar is the user's call, never yours.

If implementation reveals new work, file it (`bd create`) instead of silently expanding the
current ticket.

## The one rule that decides everything here

**Nothing in this repository is proven by reading it.** Behaviour lives in the tmux server's
state. A claim is real only after you have observed it, with the observation captured:

```sh
tmux list-panes -t '<sess>:fleet' -F '#{pane_index} #{@role} #{pane_current_command}'
tmux capture-pane -p -t '<sess>:fleet.0' | tail -40
```

A test you wrote yourself to match your own hypothesis is not an observation. An argument about
what the script should do is not an observation. `FLEET_DRY_RUN=1 ./fleet.sh` proves the composed
command only — never the behaviour.

When you close a ticket, the reason must state what you saw, not what you changed.

## Spawning a real fleet — read before you plan

`AGENTS.md` forbids running `fleet` or `fleet.sh` unprompted: each pane is a billable agent
session, and `user`-style panes (codex, devin, gemini) start spending the moment they spawn.

Three tickets below need a live fleet. Plan them so that **one** approved fleet session collects
every observation all three need, then ask the user once, in plain words, for permission to spawn
it. Tear it down when you are finished:

```sh
tmux kill-window -t '<sess>:fleet'
```

First run in a fresh tree prompts for trust in every pane, and each provider prompts differently.
You cannot answer those prompts; the user must. Say so when you ask.

## Order of work

### 1. `afox-3u9.1` — stand-down guarantee (P1)

The highest risk item in the repo. A prompt line currently asks non-claude panes to stay idle;
nothing enforces it. The acceptance criteria demand a mechanism, plus three clean spawns observed.
Read `AGENTS.md` on `prompt_style` first: only claude has a system-prompt channel, and Devin's
`--agent-config` is deliberately unwired because it validates input and then ignores it. Verify any
flag actually does something before you wire a provider to it — plant a codename, ask for it back.

### 2. `afox-702` — tmux prefix and the README Keys table

Every shortcut must be pressed against a live fleet window. Fold this into the same fleet session
as ticket 1. Fix what fails (root bindings via `bind -n` if the prefix is the cause) or delete the
row from the table. Edit `tmux.conf` in the repo — never `~/.tmux.conf`, which is a symlink to it.

### 3. `afox-3u9.2` — cost and token monitoring

The only ticket here that is plain construction. Needs a live fleet only to demonstrate the 80%
warning and the 100% stop with a deliberately low budget. Budget value goes in `.env` or
`roles.yml`, never hard-coded.

### 4. `afox-3u9.3` — agent-to-agent messaging

Blocks ticket 6. The acceptance criteria rule out `tmux send-keys` as a pass, because a human or
a script drives it. Prior attempts returned "No reachable agents", but never against a fully
booted fleet — so that result proves nothing yet. Fold the attempt into the same fleet session.
If the built-in channel genuinely does not work, a documented replacement also closes the ticket.

### 5. `afox-3u9.5` — merge / CI gate

Not a build task. It is a decision that belongs to the user. Prepare both options with their
consequences, in non-technical language, ask the user, then write their answer into `SPECS.md`
#13. Do not decide it yourself and do not write code for it.

### 6. `afox-3u9.4` — active listening (research)

Cannot start until ticket 4 is closed. The output is a written finding committed to the repo —
buildable or not, the design if yes, the reason to drop it if no. No working code is required.

`afox-5lf` ("v1 multiplexer") is **out of scope**: it has no description and no acceptance
criteria. Leave it alone.

## Housekeeping rules

- Do not commit, push, merge or rebase. Leave your work in the working tree.
- Do not touch the `# >>> tmux fleet >>>` managed block in the user's shell rc; `setup.sh` owns it.
- Code comments: 1–2 lines, only for a non-obvious "why" or a trap. The existing comments in
  `fleet.sh` are the standard — each one records a failure that happened silently.
- When a ticket closes, delete its entry from the README **Unverified** section and update the
  matching row in `SPECS.md`. The acceptance criteria name which ones.

## Reporting

After each ticket, report in this shape and then move on:

1. What changed for someone using afox, in two or three lines, no filenames and no code.
2. What you observed that proves it, and the command that produced it.
3. The ticket id and its new state.

If you cannot meet a ticket's acceptance criteria, do not close it and do not fake the evidence.
Park it: `bd update <id> --append-notes "<what blocked it, what you tried, what you observed>"`,
tell the user plainly, and go to the next ticket.
