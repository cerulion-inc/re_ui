#!/usr/bin/env bash
#
# import-upstream.sh — refresh the `upstream` branch of this sparse fork to a
# given crates.io release of `re_ui`, then tag it.
#
# Usage:   ./import-upstream.sh <VERSION>
# Example: ./import-upstream.sh 0.35.0
#
# What it does:
#   1. Downloads the crates.io tarball for <VERSION>.
#   2. Checks out the `upstream` branch and replaces its tree with the tarball
#      contents verbatim (stripping crates-io packaging artifacts
#      .cargo_vcs_info.json / Cargo.toml.orig).
#   3. Commits and tags `upstream/<VERSION>`.
#
# After this, bring the Cerulion patch forward. Before merging, main must
# contain the rev Studio pins now (PINNED, the full re_ui rev in
# cerulion-studio's native/studio-shell/Cargo.toml [patch.crates-io]):
#   git merge-base --is-ancestor "$PINNED" main || echo "stop: bring the pinned rev onto main first"
# If it prints stop, do that first. Then:
#   git checkout main && git merge upstream
# (resolve any conflicts in data/dark_theme.ron), publish the upstream and main
# branches and the upstream/<VERSION> tag, bump the rev in cerulion-studio's
# native/studio-shell/Cargo.toml [patch.crates-io] to the new main head, then
# rebuild and retest the shell (tests/reui_fork_pin.rs must pass) and commit the
# bump with the regenerated Cargo.lock. Once that bump is committed, point the
# pin/cerulion-studio tag at the same rev and publish it with a forced push
# (git push --force origin refs/tags/pin/cerulion-studio). See README.md for
# the full upgrade steps and CERULION-PATCH.md for the patch.

set -euo pipefail

if [ "$#" -ne 1 ]; then
    echo "usage: $0 <VERSION>   e.g. $0 0.35.0" >&2
    exit 2
fi

VERSION="$1"
CRATE="re_ui"
# crates.io requires a descriptive User-Agent (data-access policy).
UA="cerulion-re_ui-fork import-upstream.sh (opensource@cerulion.com)"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_ROOT"

if [ -n "$(git status --porcelain)" ]; then
    echo "error: working tree is dirty; commit or stash first." >&2
    exit 1
fi

TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

echo ">> downloading ${CRATE} ${VERSION} from crates.io ..."
curl -fsSL -A "$UA" \
    "https://crates.io/api/v1/crates/${CRATE}/${VERSION}/download" \
    -o "$TMPDIR/${CRATE}-${VERSION}.crate"

echo ">> extracting ..."
tar -xzf "$TMPDIR/${CRATE}-${VERSION}.crate" -C "$TMPDIR"
SRC="$TMPDIR/${CRATE}-${VERSION}"
if [ ! -d "$SRC" ]; then
    echo "error: expected extracted dir $SRC not found." >&2
    exit 1
fi

# Strip crates-io packaging artifacts — never part of the source tree.
rm -f "$SRC/.cargo_vcs_info.json" "$SRC/Cargo.toml.orig"

echo ">> switching to the upstream branch ..."
git checkout upstream

# Replace the whole tracked tree (except .git) with the tarball contents.
echo ">> replacing the upstream tree ..."
git rm -rq --ignore-unmatch .
cp -R "$SRC/." .
# Keep the target/ ignore that the fork carries (not part of the crate tarball).
printf '/target\n' > .gitignore
git add -A

if git diff --cached --quiet; then
    echo ">> no changes; ${CRATE} ${VERSION} is already on upstream. Tagging anyway."
else
    git commit -q -m "upstream: ${CRATE} ${VERSION} (crates.io tarball, verbatim)"
fi

git tag -f "upstream/${VERSION}"
echo ">> done. upstream is now ${CRATE} ${VERSION}, tagged upstream/${VERSION}."
echo ">> next: README.md step 2 (main must contain Studio's pinned rev before git merge upstream)."
