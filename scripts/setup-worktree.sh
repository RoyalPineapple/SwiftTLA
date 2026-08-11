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

while IFS= read -r submodule_path; do
    if [[ -d "$submodule_path" && ! -e "$submodule_path/.git" ]]; then
        stale_entry="$(find "$submodule_path" -mindepth 1 -maxdepth 1 -not -name .DS_Store -print -quit)"
        if [[ -n "$stale_entry" ]]; then
            echo "Cannot initialize submodule '$submodule_path': a non-submodule directory already exists there." >&2
            echo "Move or remove that directory, then rerun this script." >&2
            exit 1
        fi
        rm -f "$submodule_path/.DS_Store"
    fi
done < <(git config --file .gitmodules --get-regexp '^submodule\..*\.path$' | awk '{ print $2 }')

git submodule sync --recursive
git submodule update --init --recursive

echo "Submodules are ready."
