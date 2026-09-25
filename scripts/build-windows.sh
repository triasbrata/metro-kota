#!/usr/bin/env bash
# Build the Windows release from WSL, using the Flutter installed on Windows.
# Windows builds can't run from a \\wsl$ path, so the project is copied to C:\src first.
# Output folder (run metro_kota.exe inside it): C:\src\metro-kota-windows\
set -euo pipefail
cd "$(dirname "$0")/.."

win_dir=/mnt/c/src/metro-kota-build
rsync -a --delete --exclude build --exclude .dart_tool --exclude android/.gradle --exclude .idea ./ "$win_dir/"

cd /mnt/c # cmd.exe refuses a WSL (UNC) working directory
cmd.exe /c "cd /d C:\src\metro-kota-build && C:\src\flutter\bin\flutter.bat build windows --release" | tr -d '\r'
# A running copy locks metro_kota.exe
powershell.exe -NoProfile -Command "Get-Process metro_kota -ErrorAction SilentlyContinue | Stop-Process -Force; Start-Sleep 1"
rsync -a --delete "$win_dir/build/windows/x64/runner/Release/" /mnt/c/src/metro-kota-windows/
echo "App: C:\\src\\metro-kota-windows\\metro_kota.exe"
