#!/usr/bin/env sh
# Shared by setup/macos.sh and setup/windows.sh. Sourced, not run.

FLEET_OPEN="# >>> tmux fleet >>>"
FLEET_CLOSE="# <<< tmux fleet <<<"

say()  { printf '  %s\n' "$*"; }
step() { printf '\n== %s\n' "$*"; }
warn() { printf '  ! %s\n' "$*" >&2; }

# install_fleet_function <fleet.sh> <rc-file>
# Idempotent: strips any previous managed block before appending a new one.
install_fleet_function() {
  _fleet="$1"
  _rc="$2"

  [ -x "$_fleet" ] || chmod +x "$_fleet"
  mkdir -p "$(dirname "$_rc")"
  touch "$_rc"

  # An rc with no trailing newline would get the block glued onto its last line.
  if [ -s "$_rc" ] && [ "$(tail -c1 "$_rc" | wc -l)" -eq 0 ]; then
    printf '\n' >> "$_rc"
  fi

  if grep -qF "$FLEET_OPEN" "$_rc" 2>/dev/null; then
    _o=$(printf '%s' "$FLEET_OPEN"  | sed 's/[][\/.*^$]/\\&/g')
    _c=$(printf '%s' "$FLEET_CLOSE" | sed 's/[][\/.*^$]/\\&/g')
    sed "/$_o/,/$_c/d" "$_rc" > "$_rc.fleet-tmp"
    mv "$_rc.fleet-tmp" "$_rc"
  fi

  case "$_rc" in
    *config.fish)
      cat >> "$_rc" <<EOF
$FLEET_OPEN
function fleet
    "$_fleet" \$argv
end
$FLEET_CLOSE
EOF
      ;;
    *)
      cat >> "$_rc" <<EOF
$FLEET_OPEN
fleet() { "$_fleet" "\$@"; }
$FLEET_CLOSE
EOF
      ;;
  esac

  say "fleet() -> $_fleet   (in $_rc)"
}

# Which rc file the caller's login shell actually reads.
rc_for_shell() {
  case "$(basename "${SHELL:-sh}")" in
    zsh)  printf '%s\n' "$HOME/.zshrc" ;;
    bash) [ "$(uname -s)" = Darwin ] && printf '%s\n' "$HOME/.bash_profile" || printf '%s\n' "$HOME/.bashrc" ;;
    fish) printf '%s\n' "$HOME/.config/fish/config.fish" ;;
    *)    return 1 ;;
  esac
}

# set_env_key <.env> <KEY> <value> — add or replace one key, leaving the rest alone.
set_env_key() {
  _env="$1"; _key="$2"; _val="$3"
  touch "$_env"
  if grep -q "^$_key=" "$_env" 2>/dev/null; then
    grep -v "^$_key=" "$_env" > "$_env.tmp" && mv "$_env.tmp" "$_env"
  fi
  printf '%s="%s"\n' "$_key" "$_val" >> "$_env"
  say "$_key=\"$_val\"   (in $_env)"
}
