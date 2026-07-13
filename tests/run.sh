#!/usr/bin/env bash
# Self-test for tag_and_commit.sh.
#
# Guards the regression from YP6M-2978: version-bump changes left in the working
# tree (as produced by `cargo release version` / `pybump` in downstream jobs)
# must be committed, not silently dropped when nothing is explicitly staged.
#
# The tests run the real script under --dry-run with a stubbed `gh` (see
# tests/stub/gh), so they are hermetic: no network, no GitHub state mutated.
#
# Requires: git, bash, jq, yq (mikefarah), and GNU base64 (`base64 -w0`) — all
# present on GitHub-hosted ubuntu runners.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$REPO_ROOT/tag_and_commit.sh"
STUB_DIR="$REPO_ROOT/tests/stub"

# One work root, created in this (parent) shell so the EXIT trap can see and
# remove it. make_repo/run_script are invoked via command substitution, i.e. in
# subshells, so anything they register in a parent array would be lost — nesting
# their scratch dirs under $WORKROOT sidesteps that entirely.
WORKROOT="$(mktemp -d)"
trap 'rm -rf "$WORKROOT"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

# Fail loudly if the toolchain the script depends on is missing, rather than
# producing a confusing mid-script error.
for tool in git jq yq base64; do
  command -v "$tool" >/dev/null || fail "required tool not found: $tool"
done

# Build a throwaway git repo standing in for a freshly-checked-out release repo.
make_repo() {
  local dir; dir="$(mktemp -d "$WORKROOT/repo.XXXXXX")"
  git -C "$dir" init -q
  git -C "$dir" config user.email test@example.com
  git -C "$dir" config user.name "self-test"
  printf 'version = "0.1.0"\n' > "$dir/Cargo.toml"
  printf 'version: 0.1.0\n'    > "$dir/Chart.yaml"
  git -C "$dir" add -A
  git -C "$dir" commit -qm baseline
  echo "$dir"
}

# Run tag_and_commit.sh in $1 (cwd = the workspace repo) with the action's env.
run_script() {
  local workdir="$1"; shift
  local runner_temp gh_output
  runner_temp="$(mktemp -d "$WORKROOT/runner.XXXXXX")"
  gh_output="$(mktemp "$WORKROOT/ghout.XXXXXX")"
  (
    cd "$workdir"
    PATH="$STUB_DIR:$PATH" \
    GITHUB_REPOSITORY="p6m-actions/p6m-release-action" \
    GITHUB_REF_NAME="main" \
    GITHUB_ACTION_PATH="$REPO_ROOT" \
    RUNNER_TEMP="$runner_temp" \
    GITHUB_OUTPUT="$gh_output" \
    "$SCRIPT" "$@"
  )
}

# CASE A — the regression: unstaged tracked bumps + an untracked file, with
# nothing explicitly staged, must still be committed.
A="$(make_repo)"
printf 'version = "0.1.1"\n' > "$A/Cargo.toml"       # tracked, modified, unstaged
printf 'version: 0.1.1\n'    > "$A/Chart.yaml"        # tracked, modified, unstaged
printf 'generated\n'         > "$A/NEW_UNTRACKED.txt" # untracked, never staged
out_a="$(run_script "$A" --dry-run --message 'test' --tag v9.9.9)"
echo "$out_a" | grep -q '\[DRY RUN\] gh api graphql' \
  || fail "CASE A: commit path was skipped — working-tree bumps not detected"
echo "$out_a" | grep -Eq '"path": *"Cargo.toml"' \
  || fail "CASE A: modified tracked file Cargo.toml missing from commit body"
echo "$out_a" | grep -Eq '"path": *"NEW_UNTRACKED.txt"' \
  || fail "CASE A: untracked file NEW_UNTRACKED.txt missing from commit body"
pass "CASE A: unstaged tracked + untracked changes are committed"

# CASE B — a clean tree must NOT produce a commit, but the tag is still created.
B="$(make_repo)"
out_b="$(run_script "$B" --dry-run --message 'test' --tag v9.9.9)"
if echo "$out_b" | grep -q '\[DRY RUN\] gh api graphql'; then
  fail "CASE B: commit path taken on a clean tree (should be skipped)"
fi
echo "$out_b" | grep -q '\[DRY RUN\] gh api -X POST /repos/.*/git/tags' \
  || fail "CASE B: annotated tag not created on a clean tree"
pass "CASE B: clean tree tags without committing"

echo "All tests passed."
