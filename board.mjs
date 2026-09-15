#!/usr/bin/env node
// Always-on ticket board for the fleet window. Reads Beads on a timer and draws
// one line per ticket: [ ] open, [~] in progress, [x] closed and struck through.
// Runs no agent and costs nothing — it is a pane, not a role.

import { execFileSync } from 'node:child_process'

const REFRESH_MS = Number(process.env.FLEET_BOARD_REFRESH_MS || 10000)
const MARK = { open: '[ ]', in_progress: '[~]', closed: '[x]', deferred: '[-]' }
const DIM = '\x1b[2m'
const STRIKE = '\x1b[9m'
const BOLD = '\x1b[1m'
const OFF = '\x1b[0m'

const cols = () => Number(process.env.COLUMNS) || process.stdout.columns || 80

function tickets() {
  const raw = execFileSync('bd', ['list', '--all', '--flat', '--json'], {
    encoding: 'utf8',
    cwd: process.cwd(),
  })
  return JSON.parse(raw)
}

function draw() {
  let rows
  try {
    rows = tickets()
  } catch (e) {
    process.stdout.write(`\x1b[H\x1b[2Jboard: bd failed — ${e.message.split('\n')[0]}\n`)
    return
  }
  // Open work first: the board exists to show what is left, not what is done.
  const rank = (s) => (s === 'closed' ? 2 : s === 'deferred' ? 1 : 0)
  rows.sort((a, b) => rank(a.status) - rank(b.status) || a.id.localeCompare(b.id))

  const width = cols()
  const done = rows.filter((r) => r.status === 'closed').length
  const out = [`${BOLD}TICKETS${OFF} ${done}/${rows.length} done`, '']
  for (const r of rows) {
    const mark = MARK[r.status] || '[?]'
    const line = `${mark} ${r.id}  ${r.title}`.slice(0, width)
    out.push(r.status === 'closed' ? `${DIM}${STRIKE}${line}${OFF}` : line)
  }
  process.stdout.write('\x1b[H\x1b[2J' + out.join('\n') + '\n')
}

draw()
setInterval(draw, REFRESH_MS)
