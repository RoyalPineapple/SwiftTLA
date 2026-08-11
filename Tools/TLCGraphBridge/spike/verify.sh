#!/usr/bin/env bash
set -euo pipefail

bridge_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
exec swift "$bridge_root/spike/VerifyGraphEvents.swift" "$@"
