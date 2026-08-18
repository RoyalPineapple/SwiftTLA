#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/../../.." && pwd)"
runner="$root/scripts/local-validation.sh"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/swifttla-lock-test.XXXXXX")"
repo="$tmp/repo"
lock_file=""
legacy_lock_dir=""
holder_ready_file="$tmp/holder-ready"

cleanup() {
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
    lock_file="$common_git_dir/swifttla-local-validation.advisory.lock"
    legacy_lock_dir="$common_git_dir/swifttla-local-validation.lock"
else
    lock_file="$repo/$common_git_dir/swifttla-local-validation.advisory.lock"
    legacy_lock_dir="$repo/$common_git_dir/swifttla-local-validation.lock"
fi

run_static() {
    local started=$SECONDS
    set +e
    output="$(cd "$repo" && SWIFTTLA_LOCAL_VALIDATION_LOCK_WAIT_SECONDS=1 "$runner" static 2>&1)"
    status=$?
    set -e
    elapsed=$((SECONDS - started))
}

assert_wait_timeout() {
    local expected_owner="$1"
    run_static
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
}

assert_static_started() {
    run_static
    [[ "$status" -eq 2 ]] || { echo "expected git diff --check exit 2, got $status" >&2; exit 1; }
    [[ "$elapsed" -le 1 ]] || { echo "uncontended validation took ${elapsed}s" >&2; exit 1; }
    [[ "$output" == *"trailing whitespace"* ]] || {
        echo "validation command did not start: $output" >&2
        exit 1
    }
}

start_lock_holder() {
    : > "$lock_file"
    rm -f -- "$holder_ready_file"
    /usr/bin/lockf -s -k -w -t 0 "$lock_file" sh -c 'touch "$1"; sleep 2' sh "$holder_ready_file" &
    holder_pid=$!
    for _ in {1..20}; do
        [[ -f "$holder_ready_file" ]] && return
        sleep 0.1
    done
    echo "lock holder did not acquire $lock_file" >&2
    exit 1
}

start_lock_holder
assert_wait_timeout "lock owner data is unavailable"
wait "$holder_pid"
assert_static_started

start_lock_holder
printf '%s\n' "$holder_pid" > "$lock_file"
assert_wait_timeout "lock owner appears active (pid $holder_pid"
wait "$holder_pid"

start_lock_holder
stale_pid=2147483647
printf '%s\n' "$stale_pid" > "$lock_file"
assert_wait_timeout "lock owner is likely stale (pid $stale_pid"
wait "$holder_pid"

mkdir "$legacy_lock_dir"
assert_static_started
[[ -d "$legacy_lock_dir" ]] || { echo "validation removed legacy lock directory" >&2; exit 1; }

echo "local validation lock contract passed"
