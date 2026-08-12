#!/usr/bin/env zsh
# Spawn one agent pane per role in roles.yml, tiled in a "fleet" window.
# Each role names a provider from providers.yml, which owns the CLI invocation.
# Usage: fleet [session-id] [repo-path]
# FLEET_DRY_RUN=1 prints the composed per-pane command and spawns nothing —
# the only way to check a provider's flags without paying for N agent sessions.

set -e

DIR="${0:A:h}"
ROLES_FILE="$DIR/roles.yml"
WIN=fleet

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
typeset -a NAMES PROMPTS TOOLS CMDS TOOLFLAGS BINS MODELS PANES
# US (0x1f), not tab: tab is IFS whitespace, so zsh collapses runs of it and one
# empty field (a provider with no tools_flag) shifts every field after it.
while IFS=$'\x1f' read -r kind key val tools cmd toolflag bin model; do
  case "$kind" in
    CFG)  CFG[$key]="$val" ;;
    ROLE) NAMES+=("$key"); PROMPTS+=("$val"); TOOLS+=("$tools")
          CMDS+=("$cmd"); TOOLFLAGS+=("$toolflag"); BINS+=("$bin")
          MODELS+=("$model") ;;
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
  if [[ "$tpl" == *'{prompt}'* ]]; then
    tpl="${tpl%%\{prompt\}*}${(q)PROMPTS[$i]}${tpl#*\{prompt\}}"
  fi
  cmd="$tpl"
  # An empty list must drop the flag, not pass an empty argument.
  if [ -n "${TOOLS[$i]}" ] && [ -n "${TOOLFLAGS[$i]}" ]; then
    tf="${TOOLFLAGS[$i]}"
    cmd="$cmd ${tf%%\{tools\}*}${(q)TOOLS[$i]}${tf#*\{tools\}}"
  fi
  if [ -n "$FLEET_DRY_RUN" ]; then
    print -r -- "${NAMES[$i]} [${MODELS[$i]}] in $REPO"
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
tmux set-option -w -t "$SESS:$WIN" pane-border-format '#{pane_index}: #{@role} [#{@model}]'
for i in {1..${#NAMES}}; do
  tmux set-option -p -t "${PANES[$i]}" @role "${NAMES[$i]}"
  tmux set-option -p -t "${PANES[$i]}" @model "${MODELS[$i]}"
done

# Built with -d to avoid flicker, but the caller asked for it — so show it.
tmux select-window -t "$SESS:$WIN"

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
