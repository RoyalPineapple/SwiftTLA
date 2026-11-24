#!/usr/bin/env bash
set -euo pipefail

# macOS-only, deliberately narrow local diagnostic runner. Hosted Actions is
# the admission authority; this only bounds a focused command's host impact.
readonly max_rss_mib=32768
readonly min_available_mib=768
readonly poll_seconds=2
# The environment override keeps the shell-level contention regression fast.
readonly lock_wait_seconds="${SWIFTTLA_LOCAL_VALIDATION_LOCK_WAIT_SECONDS:-30}"

usage() {
    cat >&2 <<'EOF'
usage: scripts/local-validation.sh static
       scripts/local-validation.sh swiftpm-test <test-filter>
       scripts/local-validation.sh xcode-test <test-identifier>
       scripts/local-validation.sh proof-step <retained-packet> <first-line> <last-line> [candidate-proof [byte-input [caller-byte-input]]]
       append --also <first-line> <last-line> [candidate-proof [byte-input [caller-byte-input]]] for a second independent selection from that packet
       scripts/local-validation.sh proof-tools
       scripts/local-validation.sh proof-prepare <output-directory> <checked-proof> [ordered-copy-actions]
       scripts/local-validation.sh proof-prepare <output-directory> compiler-expansion
       scripts/local-validation.sh proof-prepare <output-directory> compiler-expansion-sil
       scripts/local-validation.sh proof-prepare <output-directory> compiler-expansion-function
       scripts/local-validation.sh proof-prepare <output-directory> compiler-expansion-helper
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

validate_proof_selection() {
    [[ $# -ge 2 && $# -le 5 ]] || usage
    require_positive_integer first-line "$1"
    require_positive_integer last-line "$2"
    [[ "$1" -le "$2" ]] || fail "first-line must not exceed last-line"
}

[[ "$(uname -s)" == "Darwin" ]] || fail "macOS is required"

paired=false
mode="${1:-}"
case "$mode" in
    static|proof-tools)
        [[ $# -eq 1 ]] || usage
        ;;
    swiftpm-test|xcode-test)
        [[ $# -eq 2 && -n "${2:-}" && "${2:-}" != -* ]] || usage
        selector="$2"
        ;;
    proof-step)
        packet="${2:-}"
        [[ -n "$packet" ]] || usage
        shift 2
        first_selection=()
        while [[ $# -gt 0 && "$1" != --also ]]; do
            first_selection+=("$1")
            shift
        done
        [[ ${#first_selection[@]} -ge 2 ]] || usage
        validate_proof_selection "${first_selection[@]}"
        proof_arguments=("$packet" "${first_selection[@]}")
        if [[ $# -gt 0 ]]; then
            shift
            validate_proof_selection "$@"
            for argument in "$@"; do [[ "$argument" != --also ]] || usage; done
            second_proof_arguments=("$packet" "$@")
            paired=true
        fi
        ;;
    proof-prepare)
        [[ $# -eq 3 || ( $# -eq 4 && "${4:-}" == ordered-copy-actions ) ]] || usage
        proof_arguments=("${@:2}")
        ;;
    *)
        usage
        ;;
esac

readonly common_git_dir="$(git rev-parse --git-common-dir)"
# Xcode uses private DerivedData. SwiftPM and proof preparation share a writable build cache.
if [[ "$mode" == xcode-test ]]; then
    readonly lock_file="$common_git_dir/swifttla-xcode-validation.advisory.lock"
else
    readonly lock_file="$common_git_dir/swifttla-local-validation.advisory.lock"
fi
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

drain_proof_pair() {
    [[ "$paired" == true && -n "$command_group" ]] || return 0
    local i
    for i in {1..20}; do
        kill -0 -- "-$command_group" 2>/dev/null || return 0
        sleep 0.1
    done
    kill -KILL -- "-$command_group" 2>/dev/null || return 0
    while ps -axo pgid=,stat= | awk -v group="$command_group" '
        $1 == group && $2 !~ /^Z/ { live=1 }
        END { exit !live }
    '; do sleep 0.1; done
}

cleanup() {
    terminate_group
    drain_proof_pair
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
# Block in the kernel. The lock stays on the shell's open file description.
python3 - "$lock_wait_seconds" <<'PYTHON'
import fcntl
import signal
import sys

def timeout(signum, frame):
    sys.exit(75)

signal.signal(signal.SIGALRM, timeout)
signal.alarm(int(sys.argv[1]))
fcntl.flock(9, fcntl.LOCK_EX)
PYTHON
lock_status=$?
set -e
if [[ "$lock_status" -ne 0 ]]; then
    owner="$(lock_owner_diagnostics)"
    if [[ "$lock_status" -eq 75 ]]; then
        fail "timed out after ${lock_wait_seconds}s waiting for validation lock ($lock_file); ${owner}; lock was not changed"
    fi
    fail "could not acquire validation lock ($lock_file; flock status $lock_status); ${owner}; lock was not changed"
fi

printf '%s\n' "$$" > "$lock_file"

tree_rss_mib() {
    ps -axo pid=,ppid=,rss=,pgid= | awk -v root="$1" -v paired="$paired" '
        { parent[$1] = $2; rss[$1] = $3; if (paired == "true" && $4 == root) present[$1] = 1 }
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
            if [[ "$paired" == true ]]; then touch "$scratch_dir/pair-guard-trip"; fi
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
        ruby -e 'require "yaml"; ARGV.each { |path| YAML.parse_file(path) }' \
            .github/workflows/ci.yml .github/workflows/validation-pipeline.yml \
            .github/workflows/validation-case.yml .github/actions/setup-pinned-tlaps/action.yml
        bash -n scripts/build-pinned-tlaps.sh scripts/check-language-proof-batch.sh scripts/proof-family-inputs.sh scripts/bootstrap-pinned-proof.sh
        python3 -c 'import ast, pathlib; ast.parse(pathlib.Path("scripts/check-initial-proof-step.py").read_text())'
        python3 -c 'import ast, pathlib; ast.parse(pathlib.Path("scripts/prepare-initial-proof.py").read_text())'
        python3 scripts/prepare-initial-proof.py --self-check
        bash Tests/Fixtures/LocalValidation/assert_lock.sh
        ruby Tests/Fixtures/ProofFamily/assert_routing.rb
        python3 Tests/Fixtures/TLAPSBootstrap/assert_inputs.py
        python3 "$(dirname "$0")/retain-native-initial-source.py" --self-check
        "$(dirname "$0")/setup-finite-graph-tools.sh" --verify-bridge-sources
        bash "$(dirname "$0")/verify-finite-graph-input-pins.sh"
        return
    fi

    scratch_dir="$(mktemp -d "${TMPDIR:-/tmp}/swifttla-local-validation.XXXXXX")"
    export SWIFTTLA_VALIDATION_SCRATCH_PATH="$scratch_dir"
    if [[ "$mode" == "swiftpm-test" || ( "$mode" == "proof-prepare" && "${proof_arguments[1]}" != compiler-expansion* ) ]]; then
        local cache_root="$common_git_dir/swifttla-local-validation-cache"
        local worktree_key worktree_cache
        local cache_key cache_key_file toolchain_key toolchain_key_file macro_key macro_key_file
        [[ ! -L "$cache_root" ]] || fail "cache root must not be a symlink"
        mkdir -p "$cache_root"
        # SwiftPM build records include checkout paths, so isolate worktree builds.
        worktree_key="$(git rev-parse --show-toplevel | shasum -a 256 | awk '{print $1}')"
        [[ "$worktree_key" =~ ^[0-9a-f]{64}$ ]] || fail "could not compute worktree cache key"
        worktree_cache="$cache_root/$worktree_key"
        [[ ! -L "$worktree_cache" ]] || fail "worktree cache directory must not be a symlink"
        mkdir -p "$worktree_cache"
        cache_key_file="$worktree_cache/source-key"
        toolchain_key_file="$worktree_cache/toolchain-key"
        macro_key_file="$worktree_cache/macro-source-key"
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
        macro_key="$({
            printf '%s\n' 'swiftpm-local-validation-macro-sources-v1'
            git ls-files --cached --others --exclude-standard -z -- \
                Sources/SwiftTLA Sources/SwiftTLAPlugin Sources/SwiftTLAMacros Sources/SwiftTLACompilerSupport |
                while IFS= read -r -d '' input_path; do
                    if [[ -f "$input_path" && ! -L "$input_path" ]]; then
                        shasum -a 256 -- "$input_path"
                    elif [[ -L "$input_path" ]]; then
                        printf 'symlink:%s:%s\n' "$input_path" "$(readlink "$input_path")"
                    fi
                done
        } | shasum -a 256 | awk '{print $1}')"
        [[ "$cache_key" =~ ^[0-9a-f]{64}$ ]] || fail "could not compute source cache key"
        [[ "$toolchain_key" =~ ^[0-9a-f]{64}$ ]] || fail "could not compute toolchain cache key"
        [[ "$macro_key" =~ ^[0-9a-f]{64}$ ]] || fail "could not compute macro source cache key"
        build_dir="$worktree_cache/.build"
        [[ ! -L "$build_dir" ]] || fail "cache build directory must not be a symlink"
        [[ ! -L "$cache_key_file" ]] || fail "cache key file must not be a symlink"
        [[ ! -L "$toolchain_key_file" ]] || fail "toolchain key file must not be a symlink"
        [[ ! -L "$macro_key_file" ]] || fail "macro key file must not be a symlink"
        if [[ -e "$build_dir" ]]; then
            [[ -d "$build_dir" ]] || fail "cache build path is not a directory"
            # SwiftPM does not always re-expand unchanged model files when the
            # compiler or macro implementation changes. Keep incremental test
            # edits, but invalidate generated consumers with their producer.
            if [[ ! -r "$toolchain_key_file" || "$(<"$toolchain_key_file")" != "$toolchain_key" ||
                  ! -r "$macro_key_file" || "$(<"$macro_key_file")" != "$macro_key" ]]; then
                rm -rf -- "$build_dir"
            fi
        fi
        printf '%s\n' "$toolchain_key" > "$toolchain_key_file"
        printf '%s\n' "$macro_key" > "$macro_key_file"
        printf '%s\n' "$cache_key" > "$cache_key_file"
    fi
    set -m
    case "$mode" in
        proof-tools)
            bash scripts/bootstrap-pinned-proof.sh &
            ;;
        proof-step)
            if [[ "$paired" == true ]]; then
                mkdir -p "$scratch_dir/first/cache" "$scratch_dir/second/cache"
                (
                    # Both workers stay in the one process group monitored and stopped by the watchdog.
                    set +m
                    unset TLAPM_SMT_SOLVER
                    TMPDIR="$scratch_dir/first" TLAPM_CACHE_DIR="$scratch_dir/first/cache" python3 scripts/check-initial-proof-step.py --paired-worker "${proof_arguments[@]}" &
                    first_pid=$!
                    TMPDIR="$scratch_dir/second" TLAPM_CACHE_DIR="$scratch_dir/second/cache" python3 scripts/check-initial-proof-step.py --paired-worker "${second_proof_arguments[@]}" &
                    second_pid=$!
                    first_status=0
                    second_status=0
                    wait "$first_pid" || first_status=$?
                    wait "$second_pid" || second_status=$?
                    printf 'proof-step pair: first exit %d, second exit %d\n' "$first_status" "$second_status"
                    (( first_status == 0 && second_status == 0 ))
                ) &
            else
                python3 scripts/check-initial-proof-step.py "${proof_arguments[@]}" &
            fi
            ;;
        proof-prepare)
            python3 scripts/prepare-initial-proof.py "$scratch_dir" "$build_dir" "${proof_arguments[@]}" &
            ;;
        swiftpm-test)
            swift test -Xswiftc -warnings-as-errors --disable-automatic-resolution --filter "$selector" -j 1 --scratch-path "$build_dir" &
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
    # The watchdog sleep can outlive its shell during cancellation.
    watchdog 9>&- &
    watchdog_pid=$!
    wait "$command_pid" || status=$?
    terminate_group
    drain_proof_pair
    command_group=""
    wait "$watchdog_pid" 2>/dev/null || true
    watchdog_pid=""
    if [[ -f "$scratch_dir/pair-guard-trip" ]]; then return 1; fi
    return "$status"
}

case "$mode" in
    static|swiftpm-test|xcode-test|proof-step|proof-tools|proof-prepare) run_guarded ;;
esac
