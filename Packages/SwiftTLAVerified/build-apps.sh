#!/bin/bash
set -e

cd "$(dirname "$0")"
BUILD_DIR=".build/debug"

echo "Building..."
swift build -c debug

mkdir -p "$BUILD_DIR/Camera.app/Contents/MacOS"
mkdir -p "$BUILD_DIR/BLEScanner.app/Contents/MacOS"

cp Resources/Info.plist "$BUILD_DIR/Camera.app/Contents/"
cp "$BUILD_DIR/camera" "$BUILD_DIR/Camera.app/Contents/MacOS/"

cp Resources/BLE-Info.plist "$BUILD_DIR/BLEScanner.app/Contents/Info.plist"
cp "$BUILD_DIR/ble-scan" "$BUILD_DIR/BLEScanner.app/Contents/MacOS/ble-scan"

echo ""
echo "Done. Launch with:"
echo "  open $BUILD_DIR/Camera.app"
echo "  open $BUILD_DIR/BLEScanner.app"
