#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
archive_path="$ROOT_DIR/dist/Mole-CLI.alfredworkflow"

mkdir -p "$ROOT_DIR/dist"
rm -f "$archive_path"
(
    cd "$ROOT_DIR/src"
    zip -q -r "$archive_path" . -x '.DS_Store'
)
printf '%s\n' "$archive_path"
