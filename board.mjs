#!/usr/bin/env node
// Prints the Beads ticket list as markdown checkboxes, once, then exits.
// ORCHESTRATOR runs this and shows the output in its own thread — the list is a
// snapshot in a scrolling conversation, so it is printed at the moments it matters
// (session start, and after any ticket changes state) rather than kept on screen.

import { execFileSync } from 'node:child_process'

const MARK = { open: ' ', in_progress: '~', closed: 'x', deferred: '-' }

let rows
try {
  rows = JSON.parse(execFileSync('bd', ['list', '--all', '--flat', '--json'], { encoding: 'utf8' }))
} catch (e) {
  console.error(`board: bd failed — ${e.message.split('\n')[0]}`)
  process.exit(1)
}

// Open work first: the list exists to show what is left, not what is done.
const rank = (s) => (s === 'closed' ? 2 : s === 'deferred' ? 1 : 0)
rows.sort((a, b) => rank(a.status) - rank(b.status) || a.id.localeCompare(b.id))

const done = rows.filter((r) => r.status === 'closed').length
console.log(`**Tickets — ${done}/${rows.length} done**`)
console.log()
for (const r of rows) {
  const body = `${r.id} — ${r.title}`
  console.log(`- [${MARK[r.status] || '?'}] ${r.status === 'closed' ? `~~${body}~~` : body}`)
}
