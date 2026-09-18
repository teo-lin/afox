#!/usr/bin/env sh
# Entry point: detect the platform, run the matching script under setup/.
# Both are idempotent — re-running reports what is already there and skips it.
#
#   ./setup.sh              install and wire up
#   ./setup.sh --minimal    skip the optional pieces (beads, local profile)
#
# The split is not a fork of afox. Everything that actually runs the fleet is one
# code path; these two scripts only differ in how a machine gets its tools, which
# is the one place the platforms genuinely diverge.

set -e

DIR="$(cd "$(dirname "$0")" && pwd)"

case "$(uname -s)" in
  Darwin)
    exec "$DIR/setup/macos.sh" "$@"
    ;;
  MINGW*|MSYS*|CYGWIN*)
    exec "$DIR/setup/windows.sh" "$@"
    ;;
  Linux)
    # Same work as macOS — tmux, node, the rc function. Only the install hints
    # differ, and macos.sh picks those from the package manager it finds.
    exec "$DIR/setup/macos.sh" "$@"
    ;;
  *)
    echo "unsupported platform: $(uname -s)" >&2
    echo "afox needs tmux and node; wire fleet.sh into your shell by hand." >&2
    exit 1
    ;;
esac
