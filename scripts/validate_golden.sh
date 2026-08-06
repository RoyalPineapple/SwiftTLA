#!/bin/bash
set -e
cd "$(dirname "$0")/.."
JAVA_HOME=/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home
TLC="$JAVA_HOME/bin/java -cp .build/tla-tools/tla2tools.jar tlc2.TLC"
TMP=$(mktemp -d)

PASS=0; FAIL=0
check() {
    local name=$1 expected=$2
    echo -n "$name: "
    swift run --package-path Examples "$name" > "$TMP/$name.tla" 2>/dev/null || { echo "BUILD FAIL"; FAIL=$((FAIL+1)); return; }
    echo "SPECIFICATION Spec" > "$TMP/$name.cfg"
    count=$($TLC -config "$TMP/$name.cfg" "$TMP/$name.tla" 2>&1 | grep -o '[0-9]\+ distinct states' | grep -o '[0-9]\+' || echo "0")
    if [ "$count" -eq "$expected" ]; then echo "OK ($count)"; PASS=$((PASS+1)); else echo "FAIL ($count, expected $expected)"; FAIL=$((FAIL+1)); fi
}
check HourClock 12
check DieHard 16
check Allocator 4
echo "--- $PASS passed, $FAIL failed"
rm -rf "$TMP"
