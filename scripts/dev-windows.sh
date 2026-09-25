#!/usr/bin/env bash
# Run Metro Kota on Windows (debug) from WSL, with hot reload.
# Saving any file under lib/ or assets/ copies the project to C:\src again and hot-reloads.
# Windows builds can't run from a \\wsl$ path, so it runs from the copy in C:\src.
# Stop with Ctrl+C (the app window closes too).
set -euo pipefail
cd "$(dirname "$0")/.."

win_dir=/mnt/c/src/metro-kota-build
sync() { rsync -a --delete --exclude build --exclude .dart_tool --exclude android/.gradle --exclude .idea ./ "$win_dir/"; }
sync

keys=$(mktemp -u)
mkfifo "$keys"
stamp=$(mktemp)

# ponytail: polls every second (no inotify across the Windows copy); fine for one dev.
(
  exec 3>"$keys" # flutter reads its keystrokes from here: r = hot reload
  while sleep 1; do
    if find lib assets -type f -newer "$stamp" | grep -q .; then
      touch "$stamp"
      # only the sources: a full --delete sync would wipe what flutter generated on Windows
      rsync -a --delete lib/ "$win_dir/lib/"
      rsync -a --delete assets/ "$win_dir/assets/"
      printf r >&3 && echo "↻ hot reload"
    fi
  done
) &
watcher=$!
trap 'kill $watcher 2>/dev/null; rm -f "$keys" "$stamp"; powershell.exe -NoProfile -Command "Get-Process metro_kota -ErrorAction SilentlyContinue | Stop-Process -Force"' EXIT

cd /mnt/c # cmd.exe refuses a WSL (UNC) working directory
cmd.exe /c "cd /d C:\src\metro-kota-build && C:\src\flutter\bin\flutter.bat run -d windows" <"$keys" | tr -d '\r'
