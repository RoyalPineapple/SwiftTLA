#!/bin/bash
# End-to-end TLC validation for every TLA+ operator.
# Generates .tlaModule from Swift DSL specs, runs TLC, compares state counts.
# Requires: Java 21+, tla2tools.jar (run scripts/setup-tlc.sh first)
set -e
cd "$(dirname "$0")/.."

JAVA_HOME="${JAVA_HOME:-/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home}"
TLA_JAR=".build/tla-tools/tla2tools.jar"
TLC="$JAVA_HOME/bin/java -cp $TLA_JAR tlc2.TLC"
TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT

PASS=0; FAIL=0

writetla() {
    local name=$1
    shift
    swift run --skip-build tlc-validate "$name" "$@" > "$TMP/$name.tla" 2>/dev/null || {
        echo "  $name: GENERATE FAIL"
        FAIL=$((FAIL+1))
        return 1
    }
}

check() {
    local name=$1 expected=$2
    echo -n "$name: "
    echo "SPECIFICATION Spec
CHECK_DEADLOCK FALSE
" > "$TMP/$name.cfg"
    local count
    count=$($TLC -config "$TMP/$name.cfg" "$TMP/$name.tla" 2>&1 | grep -o '[0-9]\+ distinct states' | grep -o '[0-9]\+' || echo "?")
    if [ "$count" = "$expected" ]; then
        echo "OK ($count)"
        PASS=$((PASS+1))
    else
        echo "FAIL (got $count, expected $expected)"
        FAIL=$((FAIL+1))
    fi
}

# Build the validator tool
swift build --product tlc-validate 2>/dev/null || {
    echo "BUILD FAILED"
    exit 1
}

# ---- Operator matrix: one spec per category ----

# Arithmetic: x + 1, x - 1, x * 2, x / 2, -x, x % 3
writetla arithmetic && check arithmetic 8

# Comparison: x == y, x != y, x < y, x <= y, x > y, x >= y
writetla comparison && check comparison 6

# Logic: x && y, x || y, !x
writetla logic && check logic 4

# Sets: set literal, in, subset, union, intersection, difference, cardinality
writetla sets && check sets 5

# Tuples: tuple literal, access, length, append, concat
writetla tuples && check tuples 5

# Records: record literal, field access, domain
writetla records && check records 3

# Functions: function literal, apply, except, domain
writetla functions && check functions 4

# CASE / if-then-else
writetla casexpr && check casexpr 5

# CHOOSE / forall / exists
writetla choose && check choose 4

# Enabled
writetla enabled && check enabled 3

# Nondeterministic init
writetla nondetinit && check nondetinit 3

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
