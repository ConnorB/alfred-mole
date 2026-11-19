#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
archive_path="$ROOT_DIR/dist/Mole-CLI.alfredworkflow"

# Package only the workflow's own files. When src/ is linked into Alfred,
# Alfred writes prefs.plist (the user's settings) and UI state next to them,
# and those must never ship in the archive.
workflow_files=(commands.def commands.sh icon.png info.plist launch.sh lib.sh)

mkdir -p "$ROOT_DIR/dist"
rm -f "$archive_path"
(
    cd "$ROOT_DIR/src"
    zip -q "$archive_path" "${workflow_files[@]}"
)
printf '%s\n' "$archive_path"
