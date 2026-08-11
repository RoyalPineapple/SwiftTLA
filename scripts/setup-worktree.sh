#!/usr/bin/env bash
set -euo pipefail

# Initialize the repositories that SwiftTLA pins as submodules.
# Run this after creating or switching to a fresh worktree.

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

if [[ ! -f .gitmodules ]]; then
    echo "No submodules configured."
    exit 0
fi

git submodule sync --recursive
git submodule update --init --recursive

echo "Submodules are ready."
