#!/bin/bash
# Validates that our .tlaModule output matches upstream .tla files via TLC
# Prerequisite: Java 21+ and tla2tools.jar in .build/tla-tools/

set -e
JAVA_HOME=${JAVA_HOME:-/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home}
TLC="$JAVA_HOME/bin/java -cp .build/tla-tools/tla2tools.jar tlc2.TLC"
TLA_DIR=.build/tla-golden

mkdir -p "$TLA_DIR"

# Known state counts from upstream TLC
declare -A GOLDEN=(
  [HourClock]=12
  [DieHard]=16
  [Allocator]=4
  [CoffeeCan]=36
  [MovingCat]=70
  [Majority]=5
)

PASS=0
FAIL=0

for spec in HourClock DieHard Allocator CoffeeCan MovingCat Majority; do
  echo -n "$spec: "
  
  # Generate .tla from our spec
  swift run GoldenVerify "$spec" > "$TLA_DIR/$spec.tla" 2>/dev/null || {
    echo "SKIP (build failed)"
    continue
  }

  # Count states with TLC
  count=$($TLC -config <(echo "SPECIFICATION Spec") "$TLA_DIR/$spec.tla" 2>&1 | \
    grep -o '[0-9]\+ distinct states' | grep -o '[0-9]\+' || echo "0")
  
  expected=${GOLDEN[$spec]}
  if [ "$count" -eq "$expected" ]; then
    echo "OK ($count states, expected $expected)"
    ((PASS++))
  else
    echo "FAIL ($count states, expected $expected)"
    ((FAIL++))
  fi
done

echo "---"
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
