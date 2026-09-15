#!/bin/sh
# Hold a pane before its provider exists. user-style providers get their brief as
# a first user turn, so the pane starts working at spawn; the appended stand-down
# line only asks it not to. Nothing runs here until the pane is addressed.
# Usage: hold.sh <role> <composed provider command>
role="${1:-pane}"
cmd="$2"

printf '\033[1m[afox] %s is HELD\033[0m\n' "$role"
printf 'The provider is not running yet: no turn, no tool call, no file write, no spend.\n'
printf 'Press Enter to release it, or from anywhere:\n'
printf "  tmux send-keys -t '%s' Enter\n" "$TMUX_PANE"
printf '  ./fleet.sh --release        # releases every held pane in this session\n\n'

# Any line releases; the text is discarded. Keeps release to one keypress and
# leaves the brief exactly as roles.mjs composed it.
IFS= read -r _

tmux set-option -p -t "$TMUX_PANE" @held 0 2>/dev/null || true
printf '[afox] %s released\n' "$role"
exec sh -c "$cmd"
