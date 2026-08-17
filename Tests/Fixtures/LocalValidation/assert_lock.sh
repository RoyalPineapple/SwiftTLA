#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/../../.." && pwd)"
runner="$root/scripts/local-validation.sh"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/swifttla-lock-test.XXXXXX")"
repo="$tmp/repo"
lock_dir=""

cleanup() {
    [[ -z "$lock_dir" ]] || rm -rf -- "$lock_dir"
    rm -rf -- "$tmp"
}
trap cleanup EXIT

git init -q "$repo"
git -C "$repo" config user.email lock-test@example.invalid
git -C "$repo" config user.name lock-test
printf 'clean\n' > "$repo/source.txt"
git -C "$repo" add source.txt
git -C "$repo" commit -qm fixture
printf 'trailing whitespace \n' > "$repo/source.txt"

common_git_dir="$(git -C "$repo" rev-parse --git-common-dir)"
if [[ "$common_git_dir" = /* ]]; then
    lock_dir="$common_git_dir/swifttla-local-validation.lock"
else
    lock_dir="$repo/$common_git_dir/swifttla-local-validation.lock"
fi

assert_wait_timeout() {
    local expected_owner="$1"
    local started status elapsed output
    started=$SECONDS
    set +e
    output="$(cd "$repo" && SWIFTTLA_LOCAL_VALIDATION_LOCK_WAIT_SECONDS=1 \
        SWIFTTLA_LOCAL_VALIDATION_LOCK_POLL_SECONDS=1 "$runner" static 2>&1)"
    status=$?
    set -e
    elapsed=$((SECONDS - started))

    [[ "$status" -eq 64 ]] || { echo "expected timeout exit 64, got $status" >&2; exit 1; }
    [[ "$elapsed" -ge 1 && "$elapsed" -le 3 ]] || {
        echo "expected bounded one-second wait, observed ${elapsed}s" >&2
        exit 1
    }
    [[ "$output" == *"timed out after 1s waiting for validation lock"* ]] || {
        echo "missing timeout diagnostic: $output" >&2
        exit 1
    }
    [[ "$output" == *"$expected_owner"* ]] || {
        echo "missing owner diagnostic: $output" >&2
        exit 1
    }
    [[ "$output" != *"trailing whitespace"* ]] || {
        echo "a concurrent validation command started: $output" >&2
        exit 1
    }
    [[ -d "$lock_dir" ]] || { echo "waiting invocation removed lock" >&2; exit 1; }
}

mkdir "$lock_dir"
printf '%s\n' "$$" > "$lock_dir/pid"
assert_wait_timeout "lock owner appears active (pid $$"
rm -rf -- "$lock_dir"
lock_dir=""

mkdir "$repo/.git/swifttla-local-validation.lock"
lock_dir="$repo/.git/swifttla-local-validation.lock"
printf '%s\n' "$$" > "$lock_dir/pid"
(
    sleep 1
    rm -f -- "$lock_dir/pid"
    rmdir "$lock_dir"
) &
release_pid=$!
started=$SECONDS
set +e
output="$(cd "$repo" && SWIFTTLA_LOCAL_VALIDATION_LOCK_WAIT_SECONDS=3 \
    SWIFTTLA_LOCAL_VALIDATION_LOCK_POLL_SECONDS=1 "$runner" static 2>&1)"
status=$?
set -e
wait "$release_pid"
elapsed=$((SECONDS - started))
[[ "$status" -eq 2 ]] || { echo "expected released invocation to run git diff --check, got $status" >&2; exit 1; }
[[ "$elapsed" -ge 1 && "$elapsed" -le 3 ]] || {
    echo "expected acquisition after release, observed ${elapsed}s" >&2
    exit 1
}
[[ "$output" == *"trailing whitespace"* ]] || {
    echo "released invocation did not run its validation command: $output" >&2
    exit 1
}
[[ ! -d "$lock_dir" ]] || { echo "released invocation did not clean up its own lock" >&2; exit 1; }
lock_dir=""

mkdir "$repo/.git/swifttla-local-validation.lock"
lock_dir="$repo/.git/swifttla-local-validation.lock"
stale_pid=2147483647
printf '%s\n' "$stale_pid" > "$lock_dir/pid"
assert_wait_timeout "lock owner is likely stale (pid $stale_pid"

echo "local validation lock contract passed"
