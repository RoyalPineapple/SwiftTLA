#!/bin/bash
set -e

# Run TLC on a TLA+ specification.
# Usage: ./run-tlc.sh path/to/Spec.tla [path/to/Spec.cfg]
# If no .cfg is given, assumes INVARIANT ValidPhase.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

JAVA_HOME="${JAVA_HOME:-/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home}"
TLA_JAR="$PROJECT_DIR/.build/tla-tools/tla2tools.jar"
TLC="$JAVA_HOME/bin/java -XX:+UseParallelGC -cp $TLA_JAR tlc2.TLC"

if [ $# -lt 1 ]; then
    echo "Usage: $0 <spec.tla> [spec.cfg]"
    echo "  If no .cfg, checks ValidPhase with deadlock check off."
    exit 1
fi

TLA="$1"
CFG="${2:-}"

if [ ! -f "$TLA_JAR" ]; then
    echo "TLC jar not found at $TLA_JAR"
    echo "Run: ./scripts/setup-tlc.sh"
    exit 1
fi

if [ ! -f "$TLA" ]; then
    echo "Spec not found: $TLA"
    exit 1
fi

TMP=$(mktemp -d)
trap "rm -rf $TMP" EXIT

if [ -z "$CFG" ]; then
    cat > "$TMP/spec.cfg" <<EOF
SPECIFICATION Spec
INVARIANT ValidPhase
CHECK_DEADLOCK FALSE
EOF
    CFG="$TMP/spec.cfg"
fi

echo "=== $(basename "$TLA") ==="
$TLC -config "$CFG" "$TLA" 2>&1 | grep -v "^$" | head -20

echo ""
