#!/usr/bin/env sh
# Install a `fleet` shell command pointing at fleet.sh in this directory.
# Idempotent: re-running replaces the managed block.
#
# POSIX shells only (zsh/bash/fish). PowerShell is not supported because tmux
# does not run natively on Windows — use WSL, where this script works as-is.

set -e

DIR="$(cd "$(dirname "$0")" && pwd)"
FLEET="$DIR/fleet.sh"
OPEN="# >>> tmux fleet >>>"
CLOSE="# <<< tmux fleet <<<"

command -v tmux >/dev/null 2>&1 || { echo "tmux not found; install it first" >&2; exit 1; }
[ -x "$FLEET" ] || chmod +x "$FLEET"

case "$(basename "${SHELL:-sh}")" in
  zsh)  RC="$HOME/.zshrc" ;;
  bash) [ "$(uname)" = Darwin ] && RC="$HOME/.bash_profile" || RC="$HOME/.bashrc" ;;
  fish) RC="$HOME/.config/fish/config.fish"; mkdir -p "$(dirname "$RC")" ;;
  *)    echo "unsupported shell: ${SHELL:-unknown} (need zsh, bash or fish)" >&2; exit 1 ;;
esac

touch "$RC"

# An rc file with no trailing newline would get the block glued onto its last line.
[ -s "$RC" ] && [ "$(tail -c1 "$RC" | wc -l)" -eq 0 ] && printf '\n' >> "$RC"

# Strip any previous managed block so repeated runs do not stack up.
if grep -qF "$OPEN" "$RC"; then
  sed "/$(printf '%s' "$OPEN" | sed 's/[][\/.*^$]/\\&/g')/,/$(printf '%s' "$CLOSE" | sed 's/[][\/.*^$]/\\&/g')/d" "$RC" > "$RC.fleet-tmp"
  mv "$RC.fleet-tmp" "$RC"
fi

if [ "$(basename "${SHELL:-sh}")" = fish ]; then
  cat >> "$RC" <<EOF
$OPEN
function fleet
    "$FLEET" \$argv
end
$CLOSE
EOF
else
  cat >> "$RC" <<EOF
$OPEN
fleet() { "$FLEET" "\$@"; }
$CLOSE
EOF
fi

echo "installed \`fleet\` into $RC -> $FLEET"
echo "run: exec \$SHELL   (or open a new pane) then: fleet"
