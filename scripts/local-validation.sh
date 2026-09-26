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
build_dir=""
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
    export SWIFTTLA_VALIDATION_SCRATCH_PATH="$scratch_dir"
    if [[ "$mode" == "swiftpm-test" ]]; then
        local cache_root="$common_git_dir/swifttla-local-validation-cache"
        local cache_key cache_key_file toolchain_key toolchain_key_file
        [[ ! -L "$cache_root" ]] || fail "cache root must not be a symlink"
        mkdir -p "$cache_root"
        cache_key_file="$cache_root/source-key"
        toolchain_key_file="$cache_root/toolchain-key"
        toolchain_key="$({
            printf '%s\n' \
                'swiftpm-local-validation-toolchain-v1' \
                "$(xcrun --find swift)" \
                "$(swift --version 2>&1)" \
                "$(xcrun --show-sdk-version)" \
                "${DEVELOPER_DIR:-}" \
                "${SDKROOT:-}" \
                "${SWIFT_EXEC:-}" \
                "${SWIFTFLAGS:-}"
            shasum -a 256 -- Package.swift Package.resolved
        } | shasum -a 256 | awk '{print $1}')"
        cache_key="$({
            printf '%s\n' \
                'swiftpm-local-validation-v1' \
                "$(git rev-parse --show-toplevel)" \
                "$(git rev-parse HEAD)" \
                "$(xcrun --find swift)" \
                "$(swift --version 2>&1)" \
                "$(xcrun --show-sdk-version)" \
                "${DEVELOPER_DIR:-}" \
                "${SDKROOT:-}" \
                "${SWIFT_EXEC:-}" \
                "${SWIFTFLAGS:-}"
            git ls-files --cached --others --exclude-standard -z |
                while IFS= read -r -d '' input_path; do
                    if [[ -f "$input_path" && ! -L "$input_path" ]]; then
                        printf '%s\0' "$input_path"
                    fi
                done | xargs -0 shasum -a 256 --
            git ls-files --cached --others --exclude-standard -z |
                while IFS= read -r -d '' input_path; do
                    if [[ -L "$input_path" ]]; then
                        printf 'symlink:%s:%s\n' "$input_path" "$(readlink "$input_path")"
                        if [[ -f "$input_path" ]]; then
                            shasum -a 256 -- "$input_path"
                        fi
                    fi
                done
        } | shasum -a 256 | awk '{print $1}')"
        [[ "$cache_key" =~ ^[0-9a-f]{64}$ ]] || fail "could not compute source cache key"
        [[ "$toolchain_key" =~ ^[0-9a-f]{64}$ ]] || fail "could not compute toolchain cache key"
        build_dir="$cache_root/.build"
        [[ ! -L "$build_dir" ]] || fail "cache build directory must not be a symlink"
        [[ ! -L "$cache_key_file" ]] || fail "cache key file must not be a symlink"
        [[ ! -L "$toolchain_key_file" ]] || fail "toolchain key file must not be a symlink"
        if [[ -r "$toolchain_key_file" ]] && [[ "$(<"$toolchain_key_file")" != "$toolchain_key" ]]; then
            if [[ -e "$build_dir" ]]; then
                [[ -d "$build_dir" ]] || fail "cache build path is not a directory"
                rm -rf -- "$build_dir"
            fi
        fi
        printf '%s\n' "$toolchain_key" > "$toolchain_key_file"
        printf '%s\n' "$cache_key" > "$cache_key_file"
    fi
    set -m
    case "$mode" in
        swiftpm-test)
            swift test -Xswiftc -warnings-as-errors --filter "$selector" -j 1 --scratch-path "$build_dir" &
            ;;
        xcode-test)
            package_dir="$PWD"
            while [[ ! -f "$package_dir/Package.swift" ]]; do
                parent_dir="$(dirname "$package_dir")"
                [[ "$parent_dir" != "$package_dir" ]] || fail "xcode-test requires a Swift package directory"
                package_dir="$parent_dir"
            done
            package_scheme="$(basename "$package_dir")-Package"
            (
                cd "$package_dir"
                xcodebuild test SWIFT_TREAT_WARNINGS_AS_ERRORS=YES SWIFT_SUPPRESS_WARNINGS=NO -scheme "$package_scheme" -destination 'platform=macOS' \
                    "-only-testing:$selector" -parallel-testing-enabled NO \
                    -parallel-testing-worker-count 1 -jobs 1 \
                    -derivedDataPath "$scratch_dir/DerivedData"
            ) &
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
