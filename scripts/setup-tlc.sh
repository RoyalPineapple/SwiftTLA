#!/bin/bash
# Download TLA+ tools for CI validation
set -e
TLA_DIR=.build/tla-tools
mkdir -p "$TLA_DIR"
if [ ! -f "$TLA_DIR/tla2tools.jar" ]; then
    echo "Downloading tla2tools.jar..."
    curl -sL "https://github.com/tlaplus/tlaplus/releases/download/v1.7.4/tla2tools.jar" -o "$TLA_DIR/tla2tools.jar"
    echo "Done: $TLA_DIR/tla2tools.jar"
else
    echo "Already present: $TLA_DIR/tla2tools.jar"
fi
echo "Prerequisite: Java 21+ (brew install openjdk@21)"
