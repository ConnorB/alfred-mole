#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"

shellcheck -x -P "$ROOT_DIR/src" \
    "$ROOT_DIR"/src/*.sh \
    "$ROOT_DIR"/scripts/*.sh \
    "$ROOT_DIR"/tests/*.sh
