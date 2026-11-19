#!/usr/bin/env bash
#
# Prepare a release: write the CalVer version to src/info.plist, run the
# checks, commit the version, and create the matching tag. Pushing the tag
# starts the Release workflow on GitHub.
#
# Usage: scripts/release.sh [YYYY.0M.0D]   (default: today)

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
plist="$ROOT_DIR/src/info.plist"

fail() {
    printf 'release: %s\n' "$1" >&2
    exit 1
}

version="${1:-$(date +%Y.%m.%d)}"
# BSD date rolls an invalid day over (2026.02.30 becomes 2026.03.02), so a
# round trip that changes the value means the date does not exist.
[[ "$version" =~ ^[0-9]{4}\.[0-9]{2}\.[0-9]{2}$ ]] &&
    [ "$(date -j -f %Y.%m.%d "$version" +%Y.%m.%d 2>/dev/null)" = "$version" ] ||
    fail "version must be a real date in YYYY.0M.0D form, for example 2026.08.29"
tag="v$version"

cd "$ROOT_DIR"
[ -z "$(git status --porcelain)" ] || fail "commit or stash your changes first"
! git rev-parse -q --verify "refs/tags/$tag" >/dev/null || fail "tag $tag already exists"

plutil -replace version -string "$version" "$plist"
if ! { ./scripts/lint.sh && ./tests/run.sh; }; then
    git checkout -- "$plist"
    fail "checks failed; the version change was reverted"
fi

git diff --quiet -- "$plist" || git commit --quiet -m "Release $version" -- "$plist"
git tag "$tag"

printf 'Created %s. Push it to publish the release:\n  git push origin HEAD %s\n' "$tag" "$tag"
