#!/bin/bash
# TLC parity: Swift .tlaModule vs expected distinct states (and optional upstream).
# Registry: scripts/parity_registry.json (all validated exhaustive-success models)
# Ports:    UpstreamParity.ParityCatalog
set -euo pipefail
cd "$(dirname "$0")/.."

JAVA_HOME="${JAVA_HOME:-/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home}"
TLA_JAR=".build/tla-tools/tla2tools.jar"
TLC=("$JAVA_HOME/bin/java" -XX:+UseParallelGC -cp "$TLA_JAR" tlc2.TLC)
UPSTREAM="${SWIFTTLA_UPSTREAM:-$HOME/.cache/tlaplus-Examples}"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0

ensure_tools() {
  if [[ ! -f "$TLA_JAR" ]]; then
    ./scripts/setup-tlc.sh
  fi
  if [[ ! -d "$UPSTREAM/.git" ]]; then
    echo "Cloning tlaplus/Examples → $UPSTREAM"
    git clone --depth 1 https://github.com/tlaplus/Examples.git "$UPSTREAM"
  fi
  swift build --product tlc-validate >/dev/null
}

tlc_count() {
  local tla=$1 cfg=$2
  local out count result
  out=$("${TLC[@]}" -nowarning -config "$cfg" "$tla" 2>&1) || true
  # Prefer final "N distinct states found" over "initial states: N distinct"
  count=$(echo "$out" | grep -oE '[0-9]+ distinct states found' | tail -1 | grep -oE '^[0-9]+' || \
          echo "$out" | grep -oE '[0-9]+ distinct states' | tail -1 | grep -oE '^[0-9]+' || echo "?")

  if echo "$out" | grep -q 'Invariant .* is violated'; then result="safety failure"
  elif echo "$out" | grep -q 'Model checking completed. No error'; then result="success"
  elif echo "$out" | grep -q 'Error:'; then result="error"
  else result="unknown"
  fi
  echo "$count|$result"
}

check_swift_port() {
  local id=$1 expected=$2 expected_result=$3
  local safe raw mod name_tla cfg
  safe=$(echo "$id" | tr '/ ' '__')
  raw="$TMP/${safe}.raw.tla"
  printf "%-40s " "$id"

  if ! swift run tlc-validate "$id" > "$raw" 2>/dev/null; then
    echo "GEN FAIL"; FAIL=$((FAIL+1)); return
  fi

  # TLC requires filename == MODULE name
  mod=$(grep -E '^---- MODULE' "$raw" | head -1 | sed 's/.*MODULE //;s/ ----//' | tr -d ' ')
  name_tla="$TMP/${mod}.tla"
  cfg="$TMP/${mod}.cfg"
  cp "$raw" "$name_tla"

  {
    echo "SPECIFICATION Spec"
    echo "CHECK_DEADLOCK FALSE"
    # Copy CONSTANT assignments from .tla file (ASSUME lines)
    grep '^ASSUME .* = ' "$name_tla" | sed 's/ASSUME /CONSTANT /' || true
    grep -q '^HCini ==' "$name_tla" && echo "INVARIANT HCini"
    grep -q '^TypeOK ==' "$name_tla" && echo "INVARIANT TypeOK"
    grep -q '^TypeInvariant ==' "$name_tla" && echo "INVARIANT TypeInvariant"
    grep -q '^VictoryOK ==' "$name_tla" && echo "INVARIANT VictoryOK"
    grep -q '^ExclusiveAccess ==' "$name_tla" && echo "INVARIANT ExclusiveAccess"
    grep -q '^Safe ==' "$name_tla" && echo "INVARIANT Safe"
    grep -q '^Invariants ==' "$name_tla" && echo "INVARIANT Invariants"
    grep -q '^SumMet ==' "$name_tla" && echo "INVARIANT SumMet"
    grep -q '^StateConstraint ==' "$name_tla" && echo "CONSTRAINT StateConstraint"
  } > "$cfg"

  local cr count result
  cr=$(tlc_count "$name_tla" "$cfg")
  count=${cr%%|*}; result=${cr##*|}

  if [[ "$count" == "$expected" && "$result" == "$expected_result" ]]; then
    echo "OK TLC=$count $result"
    PASS=$((PASS+1))
  else
    echo "FAIL TLC=$count/$result expected $expected/$expected_result"
    FAIL=$((FAIL+1))
  fi
}

check_upstream_baseline() {
  local id=$1 module=$2 cfg=$3 expected=$4
  printf "  upstream %-32s " "$id"
  local mp cp
  mp="$UPSTREAM/$module"
  cp="$UPSTREAM/$cfg"
  if [[ ! -f "$mp" || ! -f "$cp" ]]; then
    echo "MISS files"; return
  fi
  local tdir="$TMP/up_$RANDOM"
  mkdir -p "$tdir"
  cp "$(dirname "$mp")"/*.tla "$tdir/" 2>/dev/null || true
  cp "$cp" "$tdir/run.cfg"
  local cr count result
  cr=$(tlc_count "$tdir/$(basename "$mp")" "$tdir/run.cfg")
  count=${cr%%|*}; result=${cr##*|}
  if [[ "$count" == "$expected" ]]; then
    echo "OK TLC=$count"
  else
    echo "DIFF TLC=$count (registry $expected) $result"
  fi
}

echo "=== SwiftTLA ↔ tlaplus/Examples TLC parity ==="
echo "Upstream: $UPSTREAM"
echo
ensure_tools

echo "-- Swift ports (ParityCatalog) --"
while IFS=$'\t' read -r id expected flag notes; do
  [[ -z "$id" ]] && continue
  check_swift_port "$id" "$expected" success
done < <(swift run tlc-validate list 2>/dev/null | awk -F'\t' '{print $1"\t"$2"\t"$3"\t"$4}')

echo
echo "-- Spot-check upstream baselines --"
check_upstream_baseline "HourClock" \
  "specifications/SpecifyingSystems/HourClock/HourClock.tla" \
  "specifications/SpecifyingSystems/HourClock/HourClock.cfg" 12
check_upstream_baseline "CatOddBoxes" \
  "specifications/Moving_Cat_Puzzle/Cat.tla" \
  "specifications/Moving_Cat_Puzzle/CatOddBoxes.cfg" 30
check_upstream_baseline "CatEvenBoxes" \
  "specifications/Moving_Cat_Puzzle/Cat.tla" \
  "specifications/Moving_Cat_Puzzle/CatEvenBoxes.cfg" 48
check_upstream_baseline "AsynchInterface" \
  "specifications/SpecifyingSystems/AsynchronousInterface/AsynchInterface.tla" \
  "specifications/SpecifyingSystems/AsynchronousInterface/AsynchInterface.cfg" 12

mkdir -p "$TMP/dh"
cp "$UPSTREAM/specifications/DieHard/"*.tla "$TMP/dh/" 2>/dev/null || true
cat > "$TMP/dh/TypeOK.cfg" << 'EOF'
SPECIFICATION Spec
INVARIANT TypeOK
CHECK_DEADLOCK FALSE
EOF
printf "  upstream %-32s " "DieHard/TypeOK"
cr=$(tlc_count "$TMP/dh/DieHard.tla" "$TMP/dh/TypeOK.cfg")
echo "TLC=${cr%%|*} ${cr##*|}"

echo
echo "--- $PASS passed, $FAIL failed (Swift ports) ---"
echo "Full inventory: scripts/parity_registry.json ($(python3 -c 'import json;print(len(json.load(open("scripts/parity_registry.json"))["entries"]))') exhaustive-success models)"
echo "Coverage doc: Documentation/UpstreamParity.md"
[ "$FAIL" -eq 0 ]
