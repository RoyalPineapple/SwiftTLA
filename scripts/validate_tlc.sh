#!/bin/bash
set -e
cd "$(dirname "$0")/.."

JAVA_HOME="${JAVA_HOME:-/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home}"
TLA_JAR=".build/tla-tools/tla2tools.jar"
TLC="$JAVA_HOME/bin/java -XX:+UseParallelGC -cp $TLA_JAR tlc2.TLC"
TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT

PASS=0; FAIL=0

expected_count() {
    case $1 in
        arithmetic) echo 4 ;; comparison) echo 5 ;; logic) echo 3 ;;
        sets) echo 3 ;; tuples) echo 3 ;; records) echo 2 ;;
        functions) echo 2 ;; casexpr) echo 2 ;; choose) echo 4 ;;
        forall) echo 2 ;; *) echo ? ;;
    esac
}

build_tool() {
    swift build --product tlc-validate 2>/dev/null
}

check() {
    local name=$1
    local expected=$(expected_count "$name")
    printf "%-16s " "$name:"

    swift run tlc-validate "$name" > "$TMP/$name.tla" 2>/dev/null || {
        echo "GEN FAIL"; FAIL=$((FAIL+1)); return
    }

    echo "SPECIFICATION Spec
CHECK_DEADLOCK FALSE" > "$TMP/$name.cfg"

    local out count
    out=$($TLC -nowarning -config "$TMP/$name.cfg" "$TMP/$name.tla" 2>&1)
    count=$(echo "$out" | grep -o '[0-9]\+ distinct states' | grep -o '[0-9]\+' || echo "?")

    if [ "$count" = "$expected" ]; then
        echo "OK ($count)"; PASS=$((PASS+1))
    elif [ "$count" = "?" ]; then
        echo "TLC ERROR"
        echo "$out" | grep -i "error\|fatal\|exception" | head -3
        FAIL=$((FAIL+1))
    else
        echo "FAIL ($count, expected $expected)"; FAIL=$((FAIL+1))
    fi
}

echo "=== SwiftTLA -> TLC Operator Validation ==="
echo
build_tool
for name in arithmetic comparison logic sets tuples records functions casexpr choose forall; do
    check "$name"
done
echo
echo "--- $PASS passed, $FAIL failed ---"
[ "$FAIL" -eq 0 ]
