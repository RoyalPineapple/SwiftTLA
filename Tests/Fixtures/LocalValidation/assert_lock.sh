#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/../../.." && pwd)"
runner="$root/scripts/local-validation.sh"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/swifttla-lock-test.XXXXXX")"
repo="$tmp/repo"
lock_file=""
unrelated_lock_dir=""
holder_ready_file="$tmp/holder-ready"
pair_pid=""

cleanup() {
    if [[ -n "$pair_pid" ]]; then
        kill -TERM "$pair_pid" 2>/dev/null || true
        wait "$pair_pid" 2>/dev/null || true
    fi
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
    unrelated_lock_dir="$common_git_dir/swifttla-local-validation.lock"
else
    lock_file="$repo/$common_git_dir/swifttla-local-validation.advisory.lock"
    unrelated_lock_dir="$repo/$common_git_dir/swifttla-local-validation.lock"
fi

run_validation() {
    local started=$SECONDS
    set +e
    output="$(cd "${probe_package:-$repo}" && SWIFTTLA_LOCAL_VALIDATION_LOCK_WAIT_SECONDS=1 "$runner" "$@" 2>&1)"
    status=$?
    set -e
    elapsed=$((SECONDS - started))
}

assert_wait_timeout() {
    local expected_owner="$1"
    run_validation proof-step "$tmp" 1 1
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
    run_validation static
    [[ "$status" -eq 2 ]] || { echo "expected git diff --check exit 2 at line ${BASH_LINENO[0]}, got $status: $output" >&2; exit 1; }
    [[ "$elapsed" -le 1 ]] || { echo "uncontended validation took ${elapsed}s" >&2; exit 1; }
    [[ "$output" == *"trailing whitespace"* ]] || {
        echo "validation command did not start: $output" >&2
        exit 1
    }
}

start_lock_holder() {
    : > "$lock_file"
    rm -f -- "$holder_ready_file"
    /usr/bin/lockf -s -k -w -t 0 "$lock_file" sh -c '
        touch "$1"
        for _ in $(seq 1 150); do
            [ -e "$1" ] || exit 0
            sleep 0.1
        done
        exit 1
    ' sh "$holder_ready_file" &
    holder_pid=$!
    for _ in {1..20}; do
        [[ -f "$holder_ready_file" ]] && return
        sleep 0.1
    done
    echo "lock holder did not acquire $lock_file" >&2
    exit 1
}

release_lock_holder() {
    rm -f -- "$holder_ready_file"
    wait "$holder_pid"
}

start_lock_holder
assert_wait_timeout "lock owner data is unavailable"
assert_static_started
release_lock_holder
assert_static_started

start_lock_holder
printf '%s\n' "$holder_pid" > "$lock_file"
assert_wait_timeout "lock owner appears active (pid $holder_pid"
release_lock_holder

start_lock_holder
stale_pid=2147483647
printf '%s\n' "$stale_pid" > "$lock_file"
assert_wait_timeout "lock owner is likely stale (pid $stale_pid"
release_lock_holder

mkdir "$unrelated_lock_dir"
assert_static_started
[[ -d "$unrelated_lock_dir" ]] || { echo "validation changed unrelated lock directory" >&2; exit 1; }

# Probe routing through the real wrapper without building an Xcode project.
mkdir -p "$tmp/bin"
printf '#!/bin/sh\necho xcode-probe-ran\n' > "$tmp/bin/xcodebuild"
chmod +x "$tmp/bin/xcodebuild"
export PATH="$tmp/bin:$PATH"
touch "$repo/Package.swift"

start_lock_holder
run_validation xcode-test Probe/test
[[ "$status" -eq 0 && "$output" == *xcode-probe-ran* ]] || {
    echo "isolated Xcode check failed to overlap the original lane: $output" >&2
    exit 1
}
release_lock_holder

shared_lock_file="$lock_file"
lock_file="$(dirname "$lock_file")/swifttla-xcode-validation.advisory.lock"
start_lock_holder
run_validation xcode-test Probe/test
[[ "$status" -eq 64 && "$output" == *"waiting for exclusive Xcode validation"* && "$output" != *xcode-probe-ran* ]]
release_lock_holder
xcode_gate="$lock_file"
lock_file="$shared_lock_file"

# Model a four-CPU host and hold three real wrapper jobs open in different packages.
cat > "$tmp/bin/sysctl" <<'STUB'
#!/bin/sh
case "$*" in
    '-n hw.logicalcpu') echo 4 ;;
    '-n hw.memsize') echo 103079215104 ;;
    *) exec /usr/sbin/sysctl "$@" ;;
esac
STUB
cat > "$tmp/bin/memory_pressure" <<'STUB'
#!/bin/sh
printf 'System-wide memory free percentage: %s%%\n' "${PROBE_FREE_PERCENT:-90}"
STUB
cat > "$tmp/bin/xcodebuild" <<'STUB'
#!/bin/sh
set -eu
while [ "$1" != -derivedDataPath ]; do shift; done
printf '%s\n' "$2" > started
for i in $(seq 1 300); do
    [ ! -f hold ] && break
    sleep 0.1
done
[ ! -f hold ] && echo xcode-probe-ran
STUB
chmod +x "$tmp/bin/"{sysctl,memory_pressure,xcodebuild}
probe_pids=()
for n in 1 2 3 4; do
    mkdir "$repo/pkg$n"
    touch "$repo/pkg$n/Package.swift"
done
for n in 1 2 3; do
    touch "$repo/pkg$n/hold"
    (cd "$repo/pkg$n" && exec "$runner" xcode-test Probe/test) > "$tmp/pkg$n.log" 2>&1 &
    probe_pids+=("$!")
    for _ in {1..100}; do [[ -s "$repo/pkg$n/started" ]] && break; sleep 0.1; done
    [[ -s "$repo/pkg$n/started" ]] || { cat "$tmp/pkg$n.log" >&2; exit 1; }
    if [[ "$n" == 1 ]]; then
        probe_package="$repo/pkg4" PROBE_FREE_PERCENT=10 run_validation xcode-test Probe/test
        [[ "$status" -eq 64 && "$output" == *"waiting for validation capacity"* && ! -e "$repo/pkg4/started" ]]
        mkdir "$repo/pkg1/nested"
        probe_package="$repo/pkg1/nested" run_validation xcode-test Probe/test
        [[ "$status" -eq 64 && "$output" == *"waiting for validation lock"* ]]
    fi
done
[[ "$(sort -u "$repo"/pkg[123]/started | wc -l | tr -d ' ')" == 3 ]]
probe_package="$repo/pkg4" run_validation xcode-test Probe/test
[[ "$status" -eq 64 && "$output" == *"waiting for validation capacity"* && ! -e "$repo/pkg4/started" ]]
rm "$repo/pkg1/hold"
wait "${probe_pids[0]}"
if /usr/bin/lockf -s -k -t 0 "$xcode_gate" true; then
    echo "exclusive Xcode validation started while other packages were active" >&2
    exit 1
fi
probe_package="$repo/pkg4" run_validation xcode-test Probe/test
[[ "$status" -eq 0 && "$output" == *xcode-probe-ran* ]]
rm "$repo/pkg2/hold" "$repo/pkg3/hold"
wait "${probe_pids[1]}"
wait "${probe_pids[2]}"
# Both product modes write the same cache. Exercise real wrapper locks and scratch paths.
git -C "$repo" worktree add -q --detach "$tmp/peer" HEAD
for dir in "$repo" "$tmp/peer"; do touch "$dir/Package.swift" "$dir/Package.resolved"; done
cat > "$tmp/bin/swift" <<'STUB'
#!/bin/bash
case "$1" in
    --version) echo fixture; exit ;;
    test) echo product-test-ran; exit ;;
esac
while [[ "$1" != --scratch-path ]]; do shift; done
cache="$2"
if [[ "${3:-}" == --show-bin-path ]]; then echo "$cache"; exit; fi
mkdir -p "$cache"
touch "$cache/tlc-validate"
chmod +x "$cache/tlc-validate"
echo "$cache" > cache-path
for _ in {1..100}; do [[ ! -e hold ]] && exit 0; sleep 0.1; done
exit 1
STUB
chmod +x "$tmp/bin/swift"
start_lock_holder
touch "$repo/hold"
(cd "$repo" && exec "$runner" port-build) > "$tmp/product.log" 2>&1 &
product_pid=$!
for _ in {1..80}; do [[ -s "$repo/cache-path" ]] && break; sleep 0.1; done
[[ -s "$repo/cache-path" ]] || { cat "$tmp/product.log" >&2; exit 1; }
run_validation swiftpm-test Probe
[[ "$status" -eq 64 && "$output" == *"waiting for validation lock"* && "$output" != *product-test-ran* ]]
probe_package="$tmp/peer" PROBE_FREE_PERCENT=10 run_validation port-build
[[ "$status" -eq 64 && "$output" == *"waiting for validation capacity"* && ! -e "$tmp/peer/cache-path" ]]
probe_package="$tmp/peer" run_validation port-build
[[ "$status" -eq 0 && -x "$(<"$tmp/peer/cache-path")/tlc-validate" ]]
[[ ! "$(<"$tmp/peer/cache-path")" -ef "$(<"$repo/cache-path")" ]]
release_lock_holder
run_validation proof-prepare "$tmp/evidence" "$tmp/checked.tla"
[[ "$status" -eq 64 && "$output" == *"waiting for compiler products"* ]]
rm "$repo/hold"
wait "$product_pid"
mkdir -p "$repo/scripts"
cat > "$repo/scripts/prepare-initial-proof.py" <<'PYTHON'
from pathlib import Path
import sys
assert Path(sys.argv[2]).samefile(Path("cache-path").read_text().strip())
print("prepared-with-built-products")
PYTHON
run_validation proof-prepare "$tmp/evidence" "$tmp/checked.tla"
[[ "$status" -eq 0 && "$output" == *prepared-with-built-products* ]]
run_validation swiftpm-test Probe
[[ "$status" -eq 0 && "$output" == *product-test-ran* ]]
rm "$tmp/bin/swift"
rm "$tmp/bin/sysctl" "$tmp/bin/memory_pressure"

mkdir -p "$repo/scripts"
cat > "$repo/scripts/check-initial-proof-step.py" <<'PYTHON'
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time

args = sys.argv[1:]
paired = args[:1] == ["--paired-worker"]
if paired:
    args.pop(0)
packet, slot = Path(args[0]), args[1]


def wait_for(path):
    deadline = time.monotonic() + 15
    while not path.is_file():
        if time.monotonic() >= deadline:
            raise SystemExit(f"stub {slot}: timed out waiting for {path.name}")
        time.sleep(0.05)


if slot == "child":
    def terminated(_signum, _frame):
        (packet / "child.terminated").touch()
        raise SystemExit(0)

    signal.signal(signal.SIGTERM, terminated)
    (packet / "child.ready").touch()
    wait_for(packet / "child.unexpected-release")
    raise SystemExit("stub child was released without TERM")

if not paired:
    if args[1:] == ["3", "3"] and os.environ.get("TLAPM_SMT_SOLVER") == "fixture-invalid-solver":
        print("single worker kept its caller environment")
        raise SystemExit(0)
    raise SystemExit(f"unexpected single-worker invocation: {args[1:]}")

if args[1:] != [slot, slot] or slot not in {"1", "2"}:
    raise SystemExit(f"unexpected stub selection: {args[1:]}")
if "TLAPM_SMT_SOLVER" in os.environ:
    raise SystemExit("paired worker inherited the caller solver override")

private = Path(tempfile.gettempdir())
cache = Path(os.environ["TLAPM_CACHE_DIR"])
scratch = Path(os.environ["SWIFTTLA_VALIDATION_SCRATCH_PATH"]).resolve()
if packet.parent.resolve() not in scratch.parents or any(
    not path.is_absolute() or scratch not in path.resolve().parents for path in (private, cache)
):
    raise SystemExit("stub temporary paths escaped the fixture")
for directory, name in ((private, "result"), (cache, "fingerprint")):
    directory.mkdir(parents=True, exist_ok=True)
    with (directory / name).open("x") as output:
        output.write(slot)
if slot == "1" and (packet / "terminate").exists():
    subprocess.Popen([sys.executable, __file__, str(packet), "child"])
    wait_for(packet / "child.ready")

ready = packet / f"{slot}.starting"
ready.write_text(f"{os.getpid()}\t{os.getpgrp()}\t{os.getcwd()}\t{private}\t{cache}\t{scratch}\n")
ready.rename(packet / f"{slot}.ready")
wait_for(packet / f"{slot}.release")
(packet / f"{slot}.finished").touch()
raise SystemExit(int((packet / f"{slot}.status").read_text()))
PYTHON

wait_for_file() {
    for _ in {1..150}; do
        [[ -f "$1" ]] && return
        sleep 0.1
    done
    echo "proof fixture did not reach ${1##*/}" >&2
    cat "$pair_log" >&2
    exit 1
}

start_proof_pair() {
    local first_status="$1" second_status="$2"
    printf '%s\n' "$first_status" > "$packet/1.status"
    printf '%s\n' "$second_status" > "$packet/2.status"
    (
        cd "$repo"
        exec env TMPDIR="$tmp" TLAPM_SMT_SOLVER=fixture-invalid-solver \
            SWIFTTLA_LOCAL_VALIDATION_LOCK_WAIT_SECONDS=1 "$runner" proof-step "$packet" 1 1 --also 2 2
    ) > "$pair_log" 2>&1 &
    pair_pid=$!
    wait_for_file "$packet/1.ready"
    wait_for_file "$packet/2.ready"
    IFS=$'\t' read -r first_pid first_group first_cwd first_temp first_cache first_scratch < "$packet/1.ready"
    IFS=$'\t' read -r second_pid second_group second_cwd second_temp second_cache second_scratch < "$packet/2.ready"
    [[ "$first_pid" != "$second_pid" && "$first_group" == "$second_group" && "$first_group" != "$pair_pid" ]] &&
        kill -0 "$first_pid" "$second_pid" &&
        [[ "$first_cwd" -ef "$repo" && "$second_cwd" -ef "$repo" && "$first_scratch" == "$second_scratch" ]] &&
        [[ "$first_temp" != "$second_temp" && "$(<"$first_temp/result")" == 1 && "$(<"$second_temp/result")" == 2 ]] &&
        [[ "$first_cache" != "$second_cache" && "$(<"$first_cache/fingerprint")" == 1 && "$(<"$second_cache/fingerprint")" == 2 ]] || {
        echo "proof workers did not overlap in one isolated process group with private temporary files" >&2
        cat "$packet/"*.ready >&2
        exit 1
    }
}

finish_proof_pair() {
    local expected="$1" observed=0
    wait "$pair_pid" || observed=$?
    pair_pid=""
    [[ "$observed" -eq "$expected" ]] || {
        echo "expected proof pair exit $expected, got $observed" >&2
        cat "$pair_log" >&2
        exit 1
    }
}

for failing in 1 2; do
    packet="$tmp/proof-failure-$failing"
    pair_log="$packet/wrapper.log"
    mkdir "$packet"
    if [[ "$failing" == 1 ]]; then
        first_status=7 second_status=0
        successful=2
    else
        first_status=0 second_status=9
        successful=1
    fi
    start_proof_pair "$first_status" "$second_status"
    if [[ "$failing" == 1 ]]; then
        assert_wait_timeout "lock owner appears active (pid $pair_pid"
    fi
    touch "$packet/$failing.release"
    wait_for_file "$packet/$failing.finished"
    if [[ "$failing" == 2 ]]; then
        assert_wait_timeout "lock owner appears active (pid $pair_pid"
    fi
    touch "$packet/$successful.release"
    finish_proof_pair 1
    [[ -f "$packet/$successful.finished" ]] &&
        [[ "$(<"$pair_log")" == *"proof-step pair: first exit $first_status, second exit $second_status"* ]] || {
        echo "proof pair did not report both selection results" >&2
        cat "$pair_log" >&2
        exit 1
    }
done

packet="$tmp/proof-success"
pair_log="$packet/wrapper.log"
mkdir "$packet"
start_proof_pair 0 0
touch "$packet/1.release" "$packet/2.release"
finish_proof_pair 0

packet="$tmp/proof-terminated"
pair_log="$packet/wrapper.log"
mkdir "$packet"
touch "$packet/terminate"
start_proof_pair 0 0
kill -TERM "$pair_pid"
finish_proof_pair 130
wait_for_file "$packet/child.terminated"
[[ ! -e "$first_scratch" ]] || {
    echo "proof pair left temporary directories after TERM" >&2
    exit 1
}
assert_static_started

TLAPM_SMT_SOLVER=fixture-invalid-solver run_validation proof-step "$packet" 3 3
[[ "$status" -eq 0 && "$output" == *"single worker kept its caller environment"* ]] || {
    echo "single validation no longer uses the original proof command: $output" >&2
    exit 1
}

echo "local validation lock contract passed"
