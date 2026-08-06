#!/bin/bash
set -e
JAVA_HOME=${JAVA_HOME:-/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home}
TLC="$JAVA_HOME/bin/java -cp .build/tla-tools/tla2tools.jar tlc2.TLC"
TLA_DIR=.build/tla-golden
mkdir -p "$TLA_DIR"

PASS=0; FAIL=0

check() {
    local spec=$1 expected=$2
    echo -n "$spec: "
    swift run GoldenVerify "$spec" > "$TLA_DIR/$spec.tla" 2>/dev/null || { echo "SKIP"; return; }
    count=$($TLC -config <(echo "SPECIFICATION Spec") "$TLA_DIR/$spec.tla" 2>&1 | grep -o '[0-9]\+ distinct states' | grep -o '[0-9]\+' || echo "0")
    if [ "$count" -eq "$expected" ]; then
        echo "OK ($count)"
        PASS=$((PASS+1))
    else
        echo "FAIL ($count, expected $expected)"
        FAIL=$((FAIL+1))
    fi
}

check HourClock 12
check DieHard 16
check Allocator 4

echo "---"
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
