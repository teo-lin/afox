#!/usr/bin/env zsh
# Spawn one agent pane per role in roles.yml, tiled in a "fleet" window.
# Each role names a provider from providers.yml, which owns the CLI invocation.
# Usage: fleet [session-id] [repo-path]
#        fleet --release [session-id]   release every held pane in that fleet
#        fleet --cost [session-id]      print tokens and spend per pane
# FLEET_DRY_RUN=1 prints the composed per-pane command and spawns nothing —
# the only way to check a provider's flags without paying for N agent sessions.
# FLEET_HOLD=user|all|off picks which panes start held (default user).
# FLEET_BUDGET_USD caps spend per pane: warn at 80%, stop the pane's agent at 100%.

set -e

DIR="${0:A:h}"
ROLES_FILE="$DIR/roles.yml"
WIN=fleet
HOLD_SH="$DIR/hold.sh"
COST_MJS="$DIR/cost.mjs"
manifest_for() { print -r -- "${TMPDIR:-/tmp}/afox-fleet-${1//[^A-Za-z0-9]/_}.json" }

# A held pane has no provider process yet, so it cannot take a first turn.
HOLD_MODE="${FLEET_HOLD:-user}"
case "$HOLD_MODE" in
  user|all|off) ;;
  *) echo "FLEET_HOLD must be user, all or off (got '$HOLD_MODE')" >&2; exit 1 ;;
esac

if [ "$1" = "--cost" ]; then
  shift
  CSESS="${1:-$(tmux display-message -p '#{session_id}')}"
  CMAN="$(manifest_for "$CSESS")"
  [ -f "$CMAN" ] || { echo "no fleet manifest for $CSESS — spawn a fleet first" >&2; exit 1 }
  exec node "$COST_MJS" report "$CMAN"
fi

if [ "$1" = "--release" ]; then
  shift
  RSESS="${1:-$(tmux display-message -p '#{session_id}')}"
  HELD_PANES="$(tmux list-panes -t "$RSESS:$WIN" -F '#{pane_id} #{@held}' 2>/dev/null | awk '$2=="1"{print $1}')"
  if [ -z "$HELD_PANES" ]; then
    echo "no held panes in $RSESS:$WIN"
    exit 0
  fi
  for p in ${(f)HELD_PANES}; do
    tmux send-keys -t "$p" Enter
    echo "released $p"
  done
  exit 0
fi

# Session IDs ($43), not names: VSCode names sessions numerically, so a bare
# "36" is parsed as window index 36 half the time.
SESS="${1:-$(tmux display-message -p '#{session_id}')}"

# Machine-specific paths (CLAUDE_CONFIG_DIR) live here, not in the tracked
# files. `set -a` so roles.mjs sees them.
if [ -f "$DIR/.env" ]; then
  set -a; source "$DIR/.env"; set +a
fi

command -v node >/dev/null 2>&1 || { echo "node required to read roles.yml" >&2; exit 1 }
[ -f "$ROLES_FILE" ] || { echo "missing $ROLES_FILE" >&2; exit 1 }

# ~/.tmux.conf must symlink to this repo's tmux.conf (mouse on, prefix C-\).
# A move/rename of this repo leaves a dangling link and tmux silently falls
# back to stock defaults (mouse off, C-b) — re-point it on every run instead
# of trusting a one-time manual symlink. Only touch it if it is already a
# symlink (or absent): a real file there is the user's own config, not ours.
TMUX_CONF="$HOME/.tmux.conf"
if [ ! -e "$TMUX_CONF" ] || [ -L "$TMUX_CONF" ]; then
  if [ "$(readlink "$TMUX_CONF" 2>/dev/null)" != "$DIR/tmux.conf" ]; then
    ln -sfn "$DIR/tmux.conf" "$TMUX_CONF"
    tmux source-file "$TMUX_CONF" 2>/dev/null || true
  fi
else
  echo "warning: $TMUX_CONF exists and is not a symlink — not touching it (see README)" >&2
fi

typeset -A CFG
typeset -a NAMES PROMPTS TOOLS CMDS TOOLFLAGS BINS MODELS STYLES HELD SIDS PANES
# US (0x1f), not tab: tab is IFS whitespace, so zsh collapses runs of it and one
# empty field (a provider with no tools_flag) shifts every field after it.
while IFS=$'\x1f' read -r kind key val tools cmd toolflag bin model style; do
  case "$kind" in
    CFG)  CFG[$key]="$val" ;;
    ROLE) NAMES+=("$key"); PROMPTS+=("$val"); TOOLS+=("$tools")
          CMDS+=("$cmd"); TOOLFLAGS+=("$toolflag"); BINS+=("$bin")
          MODELS+=("$model"); STYLES+=("$style") ;;
  esac
done < <(node "$DIR/roles.mjs" "$ROLES_FILE")

# roles.mjs die()s on a bad provider or model, but it exits inside a process
# substitution, so $? here is read's — check the payload instead.
[ ${#NAMES} -gt 0 ] || { echo "roles.mjs produced no roles (see error above)" >&2; exit 1 }

# New panes inherit the cwd of whatever invoked this script, so pin it: an
# unexpected cwd means a fresh trust prompt and agents editing the wrong tree.
REPO="${2:-${CFG[repo]}}"

# A dying pane takes the whole window with it, silently — so check before any exist.
for bin in ${(u)BINS}; do
  command -v "$bin" >/dev/null 2>&1 || {
    echo "provider binary '$bin' not on PATH (see providers.yml)" >&2; exit 1
  }
done

if [ -z "$FLEET_DRY_RUN" ]; then
  tmux kill-window -t "$SESS:$WIN" 2>/dev/null || true
fi

# -d throughout so panes do not steal focus while the window is being built.
for i in {1..${#NAMES}}; do
  # Split-and-insert, not ${cmd//…}: substitution would reinterpret the
  # backslashes ${(q)…} just added.
  tpl="${CMDS[$i]}"
  # Quote every value inserted: an unquoted config_dir with a space breaks the
  # command, and one with a `;` extends it.
  # Guard on presence: %%/# against an absent placeholder both return the whole
  # template, which would silently duplicate the command instead of failing.
  if [[ "$tpl" == *'{config_dir}'* ]]; then
    tpl="${tpl%%\{config_dir\}*}${(q)CFG[config_dir]}${tpl#*\{config_dir\}}"
  fi
  # Only claude takes a session id; the others have no flag for one, so cost.mjs
  # matches their logs by repo and start time instead.
  if [[ "$tpl" == *'{role}'* ]]; then
    tpl="${tpl%%\{role\}*}${(q)NAMES[$i]}${tpl#*\{role\}}"
  fi
  sid=""
  if [[ "$tpl" == *'{session_id}'* ]]; then
    sid="$(uuidgen | tr 'A-Z' 'a-z')"
    tpl="${tpl%%\{session_id\}*}${(q)sid}${tpl#*\{session_id\}}"
  fi
  SIDS+=("$sid")
  if [[ "$tpl" == *'{prompt}'* ]]; then
    tpl="${tpl%%\{prompt\}*}${(q)PROMPTS[$i]}${tpl#*\{prompt\}}"
  fi
  cmd="$tpl"
  # An empty list must drop the flag, not pass an empty argument.
  if [ -n "${TOOLS[$i]}" ] && [ -n "${TOOLFLAGS[$i]}" ]; then
    tf="${TOOLFLAGS[$i]}"
    cmd="$cmd ${tf%%\{tools\}*}${(q)TOOLS[$i]}${tf#*\{tools\}}"
  fi
  # Held panes run hold.sh instead of the provider: the brief is composed but the
  # provider process is not started, so there is no first turn to stand down from.
  if [[ "$HOLD_MODE" == all || ( "$HOLD_MODE" == user && "${STYLES[$i]}" == user ) ]]; then
    HELD+=(1)
    cmd="${(q)HOLD_SH} ${(q)NAMES[$i]} ${(q)cmd}"
  else
    HELD+=(0)
  fi
  if [ -n "$FLEET_DRY_RUN" ]; then
    print -r -- "${NAMES[$i]} [${MODELS[$i]}]$([ "${HELD[$i]}" = 1 ] && print -n ' HELD') in $REPO"
    print -r -- "  $cmd"
    continue
  fi
  # Capture each pane's id (%12) as it is created. Pane INDEXES cannot be used to
  # label panes later: `-d` keeps pane 0 active, so every split splits pane 0 and
  # is inserted directly after it — creation order comes out reversed, and the
  # roles ended up on the wrong panes. A pane id never changes or renumbers.
  if (( i == 1 )); then
    PANES+=("$(tmux new-window -dP -F '#{pane_id}' -c "$REPO" -t "$SESS" -n "$WIN" "$cmd")")
  else
    # Split the pane just created, not the window: targeting the window splits
    # whichever pane is active (always pane 0 under -d), which inserted each new
    # pane ahead of the previous one and reversed the order roles.yml declares.
    PANES+=("$(tmux split-window -dP -F '#{pane_id}' -c "$REPO" -t "${PANES[$((i - 1))]}" "$cmd")")
  fi
done

if [ -n "$FLEET_DRY_RUN" ]; then
  exit 0
fi

tmux select-layout -t "$SESS:$WIN" tiled

# Roles live in pane-scoped user options, not pane titles: claude overwrites the
# title via OSC escape, but it cannot touch a tmux option.
tmux set-option -w -t "$SESS:$WIN" pane-border-status top
tmux set-option -w -t "$SESS:$WIN" pane-border-format '#{pane_index}: #{@role} [#{@model}] #{@cost}#{?#{==:#{@held},1}, HELD,}#{?#{==:#{@budget_state},warn}, BUDGET-WARN,}#{?#{==:#{@budget_state},stop}, BUDGET-STOP,}'
for i in {1..${#NAMES}}; do
  tmux set-option -p -t "${PANES[$i]}" @role "${NAMES[$i]}"
  tmux set-option -p -t "${PANES[$i]}" @model "${MODELS[$i]}"
  tmux set-option -p -t "${PANES[$i]}" @held "${HELD[$i]}"
done

# The monitor reads each provider's own session log, so it needs the pane ids and
# the session ids handed out above — neither exists before the panes do.
MANIFEST="$(manifest_for "$SESS")"
typeset -a MANARGS
for i in {1..${#NAMES}}; do
  MANARGS+=("${PANES[$i]}" "${NAMES[$i]}" "${MODELS[$i]%%.*}" "${MODELS[$i]}" "${STYLES[$i]}" "${SIDS[$i]}")
done
node -e '
const [out, session, window, repo, config_dir, budget, ...rest] = process.argv.slice(1)
const panes = []
for (let i = 0; i < rest.length; i += 6) {
  const [pane, role, provider, model, style, sid] = rest.slice(i, i + 6)
  panes.push({ pane, role, provider, model, style, claude_session_id: sid || null })
}
require("fs").writeFileSync(out, JSON.stringify({
  session, window, repo, config_dir,
  started_at: Math.floor(Date.now() / 1000),
  budget_usd: budget ? Number(budget) : null,
  panes,
}, null, 2))
' "$MANIFEST" "$SESS" "$WIN" "$REPO" "${CFG[config_dir]}" "${FLEET_BUDGET_USD:-}" "${MANARGS[@]}"

# One monitor per fleet: a respawn reuses the window name, so the previous monitor
# would never see its window disappear and would poll pane ids that no longer exist.
PIDFILE="${MANIFEST%.json}.pid"
[ -f "$PIDFILE" ] && kill "$(cat "$PIDFILE")" 2>/dev/null
nohup node "$COST_MJS" watch "$MANIFEST" >"${MANIFEST%.json}.log" 2>&1 &
echo $! > "$PIDFILE"
echo "cost monitor: ./fleet.sh --cost   (log: ${MANIFEST%.json}.log)"

# Built with -d to avoid flicker, but the caller asked for it — so show it.
tmux select-window -t "$SESS:$WIN"

# Closing the terminal tab only detaches tmux's client (SIGHUP); the session
# and its agent processes survive headless without this — kill it all, not
# just the fleet window.
tmux set-option -t "$SESS" destroy-unattached on

# Fleets in OTHER sessions stay running and cost real CPU; this only manages
# the current session's window.
# Literal prefix compare, not regex: session ids start with "$", which awk would
# read as an end-of-string anchor and match nothing.
OTHERS="$(tmux list-windows -a -F '#{session_id}:#{window_index} #{window_name}' | awk -v s="$SESS:" '$2=="fleet" && substr($1,1,length(s))!=s {print $1}')"
if [ -n "$OTHERS" ]; then
  echo "note: other fleet windows still running (${#NAMES} agent sessions each):"
  echo "$OTHERS" | sed 's/^/  /'
  echo "kill with: tmux kill-window -t '<target>'"
fi
