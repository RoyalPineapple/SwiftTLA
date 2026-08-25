#!/usr/bin/env bash
set -euo pipefail

# macOS-only, deliberately narrow local diagnostic runner. Hosted Actions is
# the admission authority; this only bounds a focused command's host impact.
readonly max_rss_mib=32768
readonly min_available_mib=768
readonly poll_seconds=2
# The native advisory lock waits briefly rather than failing at first collision.
# The environment override keeps the shell-level contention regression fast.
readonly lock_wait_seconds="${SWIFTTLA_LOCAL_VALIDATION_LOCK_WAIT_SECONDS:-30}"

usage() {
    cat >&2 <<'EOF'
usage: scripts/local-validation.sh static
       scripts/local-validation.sh swiftpm-test <test-filter>
       scripts/local-validation.sh xcode-test <test-identifier>
EOF
    exit 64
}

fail() {
    echo "local-validation: $*" >&2
    exit 64
}

require_positive_integer() {
    local name="$1"
    local value="$2"
    [[ "$value" =~ ^[1-9][0-9]*$ ]] || fail "$name must be a positive integer"
}

[[ "$(uname -s)" == "Darwin" ]] || fail "macOS is required"

mode="${1:-}"
case "$mode" in
    static)
        [[ $# -eq 1 ]] || usage
        ;;
    swiftpm-test|xcode-test)
        [[ $# -eq 2 && -n "${2:-}" && "${2:-}" != -* ]] || usage
        selector="$2"
        ;;
    *)
        usage
        ;;
esac

readonly common_git_dir="$(git rev-parse --git-common-dir)"
readonly lock_file="$common_git_dir/swifttla-local-validation.advisory.lock"
require_positive_integer "SWIFTTLA_LOCAL_VALIDATION_LOCK_WAIT_SECONDS" "$lock_wait_seconds"
scratch_dir=""
command_pid=""
command_group=""
watchdog_pid=""

terminate_group() {
    [[ -n "$command_group" ]] || return 0
    kill -TERM "-$command_group" 2>/dev/null || true
}

cleanup() {
    terminate_group
    if [[ -n "$watchdog_pid" ]]; then
        kill "$watchdog_pid" 2>/dev/null || true
        wait "$watchdog_pid" 2>/dev/null || true
    fi
    [[ -z "$scratch_dir" ]] || rm -rf -- "$scratch_dir"
    exec 9>&- 2>/dev/null || true
}
trap 'status=$?; cleanup; exit "$status"' EXIT
trap 'exit 130' HUP INT TERM

lock_owner_diagnostics() {
    local owner_pid="" owner_command=""
    if [[ ! -r "$lock_file" ]]; then
        printf '%s' 'lock owner data is unavailable (metadata is missing or unreadable)'
        return
    fi
    IFS= read -r owner_pid < "$lock_file" || true
    if [[ ! "$owner_pid" =~ ^[1-9][0-9]*$ ]]; then
        printf '%s' 'lock owner data is unavailable (pid is missing or invalid)'
        return
    fi
    if ! kill -0 "$owner_pid" 2>/dev/null; then
        printf 'lock owner is likely stale (pid %s has no running process)' "$owner_pid"
        return
    fi
    owner_command="$(ps -p "$owner_pid" -o command= 2>/dev/null | tr '\n' ' ' | sed 's/[[:space:]]\\+/ /g; s/^ //; s/ $//')"
    if [[ -n "$owner_command" ]]; then
        printf 'lock owner appears active (pid %s, process %s)' "$owner_pid" "$owner_command"
    else
        printf 'lock owner appears active (pid %s, process identity unavailable)' "$owner_pid"
    fi
}

exec 9>>"$lock_file"
set +e
/usr/bin/lockf -s -t "$lock_wait_seconds" 9
lock_status=$?
set -e
if [[ "$lock_status" -ne 0 ]]; then
    owner="$(lock_owner_diagnostics)"
    if [[ "$lock_status" -eq 75 ]]; then
        fail "timed out after ${lock_wait_seconds}s waiting for validation lock ($lock_file); ${owner}; lock was not changed"
    fi
    fail "could not acquire validation lock ($lock_file; lockf status $lock_status); ${owner}; lock was not changed"
fi

printf '%s\n' "$$" > "$lock_file"

tree_rss_mib() {
    ps -axo pid=,ppid=,rss= | awk -v root="$1" '
        { parent[$1] = $2; rss[$1] = $3 }
        END {
            present[root] = 1
            do {
                changed = 0
                for (pid in parent) {
                    if (present[parent[pid]] && !present[pid]) {
                        present[pid] = 1
                        changed = 1
                    }
                }
            } while (changed)
            for (pid in present) total += rss[pid]
            printf "%d\n", total / 1024
        }
    '
}

reclaimable_memory_mib() {
    local total_bytes free_percent
    total_bytes="$(sysctl -n hw.memsize)"
    free_percent="$(memory_pressure -Q | awk '/System-wide memory free percentage:/ { gsub(/[^0-9]/, "", $NF); print $NF }')"
    [[ "$free_percent" =~ ^[0-9]+$ ]] || return 1
    printf '%d\n' "$((total_bytes * free_percent / 100 / 1048576))"
}

watchdog() {
    local rss_mib reclaimable_mib reason
    while kill -0 "$command_pid" 2>/dev/null; do
        rss_mib="$(tree_rss_mib "$command_pid")"
        reclaimable_mib="$(reclaimable_memory_mib)"
        reason=""
        [[ "$rss_mib" -le "$max_rss_mib" ]] || reason="process-tree-rss"
        [[ "$reclaimable_mib" -ge "$min_available_mib" ]] || reason="reclaimable-memory"
        if [[ -n "$reason" ]]; then
            terminate_group
            printf '%s\n' \
                'guard_trip=local-validation' \
                "reason=$reason" \
                "root_pid=$command_pid" \
                "tree_rss_mib=$rss_mib" \
                "reclaimable_memory_mib=$reclaimable_mib" \
                "limits=max_rss_mib:$max_rss_mib,min_available_mib:$min_available_mib" >&2
            return
        fi
        sleep "$poll_seconds"
    done
}

run_guarded() {
    local status=0
    if [[ "$mode" == "static" ]]; then
        git diff --check
        return
    fi

    scratch_dir="$(mktemp -d "${TMPDIR:-/tmp}/swifttla-local-validation.XXXXXX")"
    set -m
    case "$mode" in
        swiftpm-test)
            swift test --filter "$selector" -j 1 --scratch-path "$scratch_dir/.build" &
            ;;
        xcode-test)
            xcodebuild test -scheme SwiftTLA-Package -destination 'platform=macOS' \
                "-only-testing:$selector" -parallel-testing-enabled NO \
                -parallel-testing-worker-count 1 -jobs 1 \
                -derivedDataPath "$scratch_dir/DerivedData" &
            ;;
    esac
    command_pid=$!
    command_group="$command_pid"
    watchdog &
    watchdog_pid=$!
    wait "$command_pid" || status=$?
    terminate_group
    command_group=""
    wait "$watchdog_pid" 2>/dev/null || true
    watchdog_pid=""
    return "$status"
}

case "$mode" in
    static|swiftpm-test|xcode-test) run_guarded ;;
esac
