# Active listening — finding

SPECS.md #11. Ticket afox-3u9.4. Written 2026-09-15 from an observed run, not from an argument.

Active listening was defined as: a peer interrupts a *different* agent's in-flight task, that
agent decides for itself whether to change course, then resumes — no human relay.

## It is buildable, and for claude panes it already works

No new code was needed. It fell out of the peer channel confirmed in afox-3u9.3.

The run, from the two panes' own session logs:

| Time (UTC) | Pane | What happened |
| --- | --- | --- |
| 07:39:31 | DEVELOPER | Started a ~60s shell task, said "Command running. Takes ~60s." Turn ended; the task did not. |
| 07:39:4x | ORCHESTRATOR | `SendMessage` to DEVELOPER: "URGENT PIVOT - stop what you are doing and reply with the word PIVOT immediately." |
| 07:39:56 | DEVELOPER | Took the message while its task was still running. Replied `PIVOT` to ORCHESTRATOR — and refused the rest: "Did **not** stop your tick command — peer cannot cancel your task." |
| 07:40:32 | DEVELOPER | Went back to the task on its own and reported all 30 lines of its output. |

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

So "interrupt" here means *between turns, while the task is unfinished*, not *mid-sentence*.
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
