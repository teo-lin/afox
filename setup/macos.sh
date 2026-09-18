#!/usr/bin/env sh
# macOS setup (and Linux — the work is identical, only the install hints differ).
#
# Deliberately installs nothing on its own: on macOS the package manager is the
# user's, and a setup script that runs `brew install` behind your back is worse
# than one that tells you what is missing. It checks, reports, and wires up the
# `fleet` command.
#
#   ./setup.sh                 check and wire up
#   ./setup.sh --minimal       skip the local-profile checks

set -e

DIR="$(cd "$(dirname "$0")/.." && pwd)"
. "$DIR/setup/common.sh"

MINIMAL=""
[ "$1" = "--minimal" ] && MINIMAL=1

if [ "$(uname -s)" = Darwin ]; then
  INSTALL="brew install"
elif command -v apt >/dev/null 2>&1; then
  INSTALL="sudo apt install"
else
  INSTALL="your package manager"
fi

MISSING=""

step "Required"
for tool in tmux node; do
  if command -v "$tool" >/dev/null 2>&1; then
    case "$tool" in
      tmux) say "tmux  $(tmux -V | awk '{print $2}')" ;;
      node) say "node  $(node --version)" ;;
    esac
  else
    warn "$tool is missing    ->  $INSTALL $tool"
    MISSING="$MISSING $tool"
  fi
done

step "Issue tracking"
if command -v bd >/dev/null 2>&1; then
  say "bd    $(bd --version 2>/dev/null | head -1)"
else
  warn "bd is missing — board.mjs and the ticket workflow need it"
  warn "  ->  npm install -g @beads/bd"
fi

if [ -z "$MINIMAL" ]; then
  step "Local, zero-spend profile (roles.local.yml)"
  for tool in ollama goose; do
    if command -v "$tool" >/dev/null 2>&1; then
      say "$tool found"
    else
      case "$tool" in
        ollama) warn "ollama is missing  ->  $INSTALL ollama, then: ollama pull qwen3:8b" ;;
        goose)  warn "goose is missing   ->  see block.github.io/goose (needs >= 1.51 for session --system)" ;;
      esac
    fi
  done
fi

step "Providers named in roles.yml"
# Missing provider binaries are not fatal here: fleet.sh checks them at spawn,
# and a fleet that only uses some of them is a normal thing to want.
for tool in claude codex devin gemini; do
  command -v "$tool" >/dev/null 2>&1 && say "$tool found" || say "$tool absent (only needed if a role uses it)"
done

step "The fleet command"
if RC="$(rc_for_shell)"; then
  install_fleet_function "$DIR/fleet.sh" "$RC"
else
  warn "unsupported shell: ${SHELL:-unknown} — need zsh, bash or fish"
  warn "call fleet.sh by path instead"
fi

step "tmux config"
TMUX_CONF="$HOME/.tmux.conf"
if [ -e "$TMUX_CONF" ] && [ ! -L "$TMUX_CONF" ]; then
  warn "$TMUX_CONF exists and is not a symlink — left alone; fleet.sh will warn too"
else
  say "fleet.sh re-points $TMUX_CONF at the repo's tmux.conf on every run"
fi

if [ -n "$MISSING" ]; then
  printf '\nInstall the missing tools above, then re-run this script.\n'
  exit 1
fi

printf '\nDone. Open a new shell (or: exec $SHELL), then from a repo:\n\n  fleet                            the fleet in roles.yml\n  FLEET_ROLES=roles.local.yml fleet    the local, zero-spend one\n\n'
