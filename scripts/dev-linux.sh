#!/usr/bin/env bash
# Run Metro Kota as a Linux desktop app (WSLg) with hot reload.
# Saving any .dart file under lib/ hot-reloads automatically.
# In this terminal: r = hot reload, R = hot restart, q = quit.
set -euo pipefail
cd "$(dirname "$0")/.."

# WSLg display defaults, for shells that don't set them.
export DISPLAY="${DISPLAY:-:0}"
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/mnt/wslg/runtime-dir}"

pidfile=$(mktemp)
stamp=$(mktemp)
rm -f "$pidfile" # flutter creates it once the app is running

# ponytail: polls lib/ every second (no inotify-tools needed); swap for inotifywait if it lags.
(
  while sleep 1; do
    if [[ -s $pidfile ]] && find lib -name '*.dart' -newer "$stamp" | grep -q .; then
      touch "$stamp"
      kill -USR1 "$(cat "$pidfile")" 2>/dev/null && echo "↻ hot reload"
    fi
  done
) &
watcher=$!
trap 'kill $watcher 2>/dev/null; rm -f "$pidfile" "$stamp"' EXIT

flutter run -d linux --pid-file "$pidfile" "$@"
