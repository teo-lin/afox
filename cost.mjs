#!/usr/bin/env node
// Per-pane token and spend accounting for a running fleet.
//   cost.mjs report <manifest>   one table, then exit
//   cost.mjs watch  <manifest>   poll, publish to the pane borders, enforce the budget
// Usage comes from each provider's own session log, never from an estimate: a
// provider that writes no token counts is reported as unmeasured, not as zero.

import { readFileSync, readdirSync, statSync, existsSync } from 'node:fs'
import { execFileSync } from 'node:child_process'
import { homedir } from 'node:os'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'

const [mode, manifestPath] = process.argv.slice(2)
if (!mode || !manifestPath) {
  console.error('usage: cost.mjs report|watch <manifest.json>')
  process.exit(1)
}

const POLL_MS = 15000
const WARN_AT = 0.8

let manifest = JSON.parse(readFileSync(manifestPath, 'utf8'))
// fileURLToPath, not URL.pathname: on Windows the pathname keeps a leading slash
// before the drive (/C:/...), which join() then resolves against the current drive
// as C:\C:\... and the monitor dies on a file that is plainly there.
const prices = readPrices(join(dirname(fileURLToPath(import.meta.url)), 'prices.yml'))

// Same shape as roles.mjs's parser: top-level key, one level of indented scalars.
// Keys here carry dots (claude.opus), so the key pattern is wider than roles.mjs's.
function readPrices(path) {
  const out = {}
  let current = null
  for (const line of readFileSync(path, 'utf8').split('\n')) {
    if (/^\s*#/.test(line) || line.trim() === '') continue
    let m
    if ((m = line.match(/^([A-Za-z0-9_.-]+):\s*$/))) current = out[m[1]] = {}
    else if (current && (m = line.match(/^\s+([a-z_]+):\s*([0-9.]+)\s*$/))) current[m[1]] = Number(m[2])
  }
  return out
}

const tmux = (...args) => {
  try {
    return execFileSync('tmux', args, { encoding: 'utf8' }).trim()
  } catch {
    return null
  }
}

const emptyTokens = () => ({ input: 0, cache_write: 0, cache_read: 0, output: 0 })
const totalOf = (t) => t.input + t.cache_write + t.cache_read + t.output

function spendOf(model, t) {
  const p = prices[model]
  if (!p) return null
  return (
    (t.input * p.input + t.cache_write * p.cache_write + t.cache_read * p.cache_read + t.output * p.output) /
    1e6
  )
}

// Claude names its log after the session id fleet.sh passed to --session-id, under
// a project folder whose name is the repo path with every non-alphanumeric run replaced.
function claudeUsage(pane) {
  if (!pane.claude_session_id) return null
  const slug = manifest.repo.replace(/[^a-zA-Z0-9]/g, '-')
  const file = join(manifest.config_dir, 'projects', slug, `${pane.claude_session_id}.jsonl`)
  if (!existsSync(file)) return emptyTokens()
  const t = emptyTokens()
  for (const line of readFileSync(file, 'utf8').split('\n')) {
    if (!line.startsWith('{')) continue
    let u
    try {
      u = JSON.parse(line)?.message?.usage
    } catch {
      continue
    }
    if (!u) continue
    t.input += u.input_tokens || 0
    t.cache_write += u.cache_creation_input_tokens || 0
    t.cache_read += u.cache_read_input_tokens || 0
    t.output += u.output_tokens || 0
  }
  return t
}

function walk(dir, out = []) {
  let entries
  try {
    entries = readdirSync(dir, { withFileTypes: true })
  } catch {
    return out
  }
  for (const e of entries) {
    const p = join(dir, e.name)
    if (e.isDirectory()) walk(p, out)
    else if (e.name.startsWith('rollout-') && e.name.endsWith('.jsonl')) out.push(p)
  }
  return out
}

// Codex has no flag to pin a session id, so a pane's log is identified by the repo
// it recorded and by having been created after the fleet started.
let codexClaimed = new Map()
function codexUsage(pane) {
  const home = process.env.CODEX_HOME || join(homedir(), '.codex')
  if (codexClaimed.has(pane.pane)) {
    const f = codexClaimed.get(pane.pane)
    return f ? sumCodex(f) : emptyTokens()
  }
  const taken = new Set(codexClaimed.values())
  const candidates = walk(join(home, 'sessions'))
    .filter((f) => statSync(f).mtimeMs >= manifest.started_at * 1000 && !taken.has(f))
    .sort((a, b) => statSync(a).mtimeMs - statSync(b).mtimeMs)
  for (const f of candidates) {
    const first = readFileSync(f, 'utf8').split('\n', 1)[0]
    let meta
    try {
      meta = JSON.parse(first)
    } catch {
      continue
    }
    const cwd = meta?.payload?.cwd || meta?.cwd
    if (cwd && cwd !== manifest.repo) continue
    codexClaimed.set(pane.pane, f)
    return sumCodex(f)
  }
  return emptyTokens()
}

// token_count carries a running total, so the last one wins; summing them double-counts.
function sumCodex(file) {
  const t = emptyTokens()
  let last = null
  for (const line of readFileSync(file, 'utf8').split('\n')) {
    if (!line.includes('token_count')) continue
    try {
      const d = JSON.parse(line)
      if (d?.payload?.type === 'token_count') last = d.payload.info?.total_token_usage || last
    } catch {
      /* a half-written last line is normal while the session is live */
    }
  }
  if (!last) return t
  t.cache_read = last.cached_input_tokens || 0
  t.input = Math.max(0, (last.input_tokens || 0) - t.cache_read)
  t.cache_write = last.cache_write_input_tokens || 0
  t.output = last.output_tokens || 0
  return t
}

function usageFor(pane) {
  if (pane.provider === 'claude') return claudeUsage(pane)
  if (pane.provider === 'codex') return codexUsage(pane)
  return null
}

function snapshot() {
  return manifest.panes.map((pane) => {
    const held = tmux('display-message', '-p', '-t', pane.pane, '#{@held}') === '1'
    const tokens = held ? emptyTokens() : usageFor(pane)
    const spend = tokens ? spendOf(pane.model, tokens) : null
    return { pane, held, tokens, spend }
  })
}

function money(n) {
  return n === null ? '—' : `$${n.toFixed(4)}`
}

function report(rows) {
  const budget = manifest.budget_usd
  const w = (s, n) => String(s).padEnd(n)
  const lines = [w('ROLE', 14) + w('MODEL', 22) + w('TOKENS', 12) + w('SPEND', 12) + 'STATE']
  let total = 0
  for (const r of rows) {
    const tok = r.tokens ? totalOf(r.tokens).toLocaleString('en-US') : 'unmeasured'
    if (r.spend) total += r.spend
    let state = r.held ? 'held' : 'running'
    if (!r.tokens) state = 'no usage log'
    else if (r.spend === null) state = 'price unset'
    else if (budget && r.spend >= budget) state = 'BUDGET STOP'
    else if (budget && r.spend >= budget * WARN_AT) state = 'BUDGET WARN'
    lines.push(w(r.pane.role, 14) + w(r.pane.model, 22) + w(tok, 12) + w(money(r.spend), 12) + state)
  }
  lines.push('')
  lines.push(`fleet total ${money(total)}${budget ? ` · budget ${money(budget)} per pane` : ' · no budget set'}`)
  return lines.join('\n')
}

// Disabling the pane's input is the stop: tmux then drops keys from a person and
// from send-keys alike, so no further turn can be submitted. SIGSTOP was tried first
// and does not hold on this machine — the process is continued again within a second.
// A turn already in flight is allowed to finish; raising budget_usd in the manifest
// re-enables the pane on the next poll.
const setInput = (pane, on) => tmux('select-pane', on ? '-e' : '-d', '-t', pane)
const inputOff = (pane) => tmux('display-message', '-p', '-t', pane, '#{pane_input_off}') === '1'

const announced = new Map()
function enforce(rows) {
  const budget = manifest.budget_usd
  for (const r of rows) {
    const label = r.spend === null ? '' : money(r.spend)
    let state = 'ok'
    if (budget && r.spend !== null) {
      const pct = r.spend / budget
      if (pct >= 1) state = 'stop'
      else if (pct >= WARN_AT) state = 'warn'
    }
    tmux('set-option', '-p', '-t', r.pane.pane, '@cost', label)
    tmux('set-option', '-p', '-t', r.pane.pane, '@budget_state', state)
    if (state !== 'ok' && announced.get(r.pane.pane) !== state) {
      announced.set(r.pane.pane, state)
      const pct = Math.round((r.spend / budget) * 100)
      tmux('display-message', '-t', r.pane.pane, `${r.pane.role}: ${pct}% of ${money(budget)} budget`)
      console.log(`${new Date().toISOString()} ${r.pane.role} ${state} ${money(r.spend)} (${pct}%)`)
    }
    if (state === 'stop') setInput(r.pane.pane, false)
    else if (inputOff(r.pane.pane)) setInput(r.pane.pane, true)
  }
}

if (mode === 'report') {
  console.log(report(snapshot()))
  process.exit(0)
}

if (mode !== 'watch') {
  console.error(`unknown mode "${mode}"`)
  process.exit(1)
}

// The window outliving the monitor is fine; the monitor outliving the window is not.
const tick = () => {
  if (!tmux('list-panes', '-t', `${manifest.session}:${manifest.window}`)) {
    console.log('fleet window gone, monitor exiting')
    process.exit(0)
  }
  try {
    // Re-read so a budget raised while the fleet runs takes effect on the next poll.
    manifest = JSON.parse(readFileSync(manifestPath, 'utf8'))
    enforce(snapshot())
  } catch (e) {
    console.log(`poll failed: ${e.message}`)
  }
}
tick()
setInterval(tick, POLL_MS)
