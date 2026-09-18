#!/usr/bin/env node
// Reads roles.yml + providers.yml and emits one record per line for fleet.sh,
// fields separated by US (0x1f):
//   CFG<US>key<US>value
//   ROLE<US>name<US>prompt<US>tools<US>cmd<US>tools_flag<US>bin<US>provider.model<US>prompt_style
// Not tab: tab is IFS whitespace, so zsh's `read` collapses runs of them and an
// empty field (a provider with no tools_flag) silently shifts every later one.
// Handles only the subset these files use: scalars, `|` blocks, a `roles:` list,
// and one nesting level of provider definitions. A real parser would mean a new
// dependency — Node has no built-in YAML and yq/PyYAML are not installed here.

import { readFileSync } from 'node:fs'
import { homedir } from 'node:os'
import { dirname, join, resolve } from 'node:path'

// Providers with no system-prompt channel get the brief as a user turn, which
// reads as "do this now" — without this line the pane starts working at spawn.
const STAND_DOWN =
  'This message is your standing role, not a task. Do not start work: reply with one line naming your role, then wait for instructions.'

const file = process.argv[2]
if (!file) {
  console.error('usage: roles.mjs <roles.yml> [providers.yml]')
  process.exit(1)
}
const providersFile = process.argv[3] || join(dirname(file), 'providers.yml')

const die = (msg) => { console.error(msg); process.exit(1) }

const US = '\x1f'

const lines = readFileSync(file, 'utf8').split('\n')
const indent = (s) => s.match(/^ */)[0].length
const isComment = (s) => /^\s*#/.test(s) || s.trim() === ''

// Consume a `|` block scalar: every following line indented deeper than `base`.
// A comment ends the block like any other dedent. The old guard let a comment
// through at any indent and then pushed it, so a `#` line between `peer: |` and
// `roles:` was appended to the text and shipped inside every role's prompt.
function block(i, base) {
  const out = []
  while (i < lines.length) {
    const line = lines[i]
    if (line.trim() === '') { i++; continue }
    if (indent(line) <= base) break
    if (!/^\s*#/.test(line)) out.push(line.trim())
    i++
  }
  return [out.join(' '), i]
}

// `name:` alone on a line, then indented `key: value`. `models:` is the only list.
function parseProviders(path) {
  let text
  try {
    text = readFileSync(path, 'utf8')
  } catch {
    die(`missing ${path} — the provider registry roles.yml selects from`)
  }
  const out = {}
  let current = null
  for (const line of text.split('\n')) {
    if (isComment(line)) continue
    let m
    if ((m = line.match(/^([A-Za-z_][\w-]*):\s*$/))) {
      current = out[m[1]] = { name: m[1] }
    } else if (current && (m = line.match(/^\s+([A-Za-z_][\w-]*):\s*(.+)$/))) {
      const [, key, raw] = m
      current[key] =
        key === 'models'
          ? raw.replace(/^\[|\]$/g, '').split(',').map((s) => s.trim()).filter(Boolean)
          : raw.trim()
    }
  }
  for (const p of Object.values(out)) {
    for (const k of ['bin', 'cmd']) {
      if (!p[k]) die(`providers.yml: "${p.name}" is missing "${k}"`)
    }
    if (!p.models?.length) die(`providers.yml: "${p.name}" has no models`)
    p.prompt_style ||= 'user'
    if (!['system', 'user'].includes(p.prompt_style)) {
      die(`providers.yml: "${p.name}" prompt_style must be system or user (got "${p.prompt_style}")`)
    }
    // Without {prompt} the brief is dropped silently and the pane has no role.
    if (!p.cmd.includes('{prompt}')) die(`providers.yml: "${p.name}" cmd has no {prompt}`)
  }
  return out
}

// Split once, not on every dot: model names contain them (gpt-5.4).
// No model = the provider's first.
function resolveProvider(spec, roleName, providers) {
  const dot = spec.indexOf('.')
  const name = dot === -1 ? spec : spec.slice(0, dot)
  const provider = providers[name]
  if (!provider) {
    die(`roles.yml: role ${roleName} wants provider "${name}"; providers.yml has: ${Object.keys(providers).join(', ')}`)
  }
  const model = dot === -1 ? provider.models[0] : spec.slice(dot + 1)
  if (!provider.models.includes(model)) {
    die(`roles.yml: role ${roleName} wants ${name}.${model}; allowed models: ${provider.models.join(', ')}`)
  }
  return { provider, model }
}

const cfg = {}
const roles = []
let i = 0

while (i < lines.length) {
  const line = lines[i]
  if (isComment(line)) { i++; continue }

  // roles: — list of "- name:" items, each optionally followed by "prompt: |"
  if (/^roles:\s*$/.test(line)) {
    i++
    let current = null
    while (i < lines.length) {
      if (isComment(lines[i])) { i++; continue }
      if (indent(lines[i]) === 0) break            // back to top level
      const t = lines[i].trim()
      let m
      if ((m = t.match(/^-\s*name:\s*(.+)$/))) {
        current = { name: m[1].trim(), prompt: '' }
        roles.push(current)
        i++
      } else if ((m = t.match(/^provider:\s*(.+)$/))) {
        if (current) current.provider = m[1].trim()
        i++
      } else if ((m = t.match(/^tools:\s*(.+)$/))) {
        // Verbatim — these are real permission names, not an alias scheme.
        if (current) {
          current.tools = m[1]
            .split(',')
            .map((s) => s.trim())
            .filter(Boolean)
            .join(',')
        }
        i++
      } else if (/^prompt:\s*\|\s*$/.test(t)) {
        const base = indent(lines[i])
        i++
        const [text, next] = block(i, base)
        if (current) current.prompt = text
        i = next
      } else {
        i++
      }
    }
    continue
  }

  // top-level  key: |   or   key: value
  let m
  if ((m = line.match(/^([A-Za-z_][\w-]*):\s*\|\s*$/))) {
    const [text, next] = block(i + 1, 0)
    cfg[m[1]] = text
    i = next
  } else if ((m = line.match(/^([A-Za-z_][\w-]*):\s*(.*)$/))) {
    cfg[m[1]] = m[2].trim().replace(/^['"]|['"]$/g, '')
    i++
  } else {
    i++
  }
}

// Paths live in .env; roles.yml only names the variable. fleet.sh sources .env
// before calling this, so the values are in the environment.
function expandPath(value, key) {
  const filled = value.replace(/\$\{([A-Za-z_]\w*)(?::-([^}]*))?\}/g, (_, name, fallback) => {
    const v = process.env[name] || fallback
    if (v === undefined) die(`roles.yml: "${key}" needs $${name} — set it in .env (see .env.example)`)
    return v
  })
  const tilde = filled.startsWith('~/') ? join(homedir(), filled.slice(2)) : filled
  return resolve(tilde)
}

for (const k of ['repo', 'config_dir']) {
  if (!cfg[k]) die(`roles.yml: missing "${k}"`)
  cfg[k] = expandPath(cfg[k], k)
}
if (roles.length === 0) die('roles.yml: no roles defined')

const providers = parseProviders(providersFile)

const out = []
out.push(['CFG', 'repo', cfg.repo].join(US))
out.push(['CFG', 'config_dir', cfg.config_dir].join(US))
for (const r of roles) {
  const spec = r.provider || cfg.provider || 'claude'
  const { provider, model } = resolveProvider(spec, r.name, providers)
  // tools_flag absent means `tools:` cannot reach this provider at all; say so
  // rather than promising the role a pre-approved list it will never have.
  const owned = r.tools && provider.tools_flag ? `Tools pre-approved for you: ${r.tools}.` : ''
  const full = [
    `ROLE: ${r.name}.`,
    r.prompt,
    owned,
    cfg.peer || '',
    provider.peer || '',
    provider.prompt_style === 'user' ? STAND_DOWN : '',
  ]
    .join(' ')
    .replace(/\s+/g, ' ')
    .trim()

  // Only {model} is safe to inline here. {prompt} {tools} {config_dir} are left
  // for fleet.sh, which shell-quotes them — a path with a space or `;` in it
  // would otherwise break or extend the command tmux runs.
  const fill = (s) => s.replaceAll('{model}', model)
  out.push(
    [
      'ROLE',
      r.name,
      full,
      r.tools || '',
      fill(provider.cmd),
      provider.tools_flag ? fill(provider.tools_flag) : '',
      provider.bin,
      `${provider.name}.${model}`,
      provider.prompt_style,
    ]
      // A US anywhere in a value would split it into two fields downstream.
      .map((f) => f.replaceAll(US, ' '))
      .join(US),
  )
}
process.stdout.write(out.join('\n') + '\n')
