#!/usr/bin/env bash
set -euo pipefail

[[ $# -eq 1 ]] || exit 64
case "$1" in
    scoped-action-binding)
        printf '%s\n' 'batch=Verification/Semantics/scoped-action-binding.batch' 'tests=LexicalBindingTests'
        ;;
    boolean-expression)
        printf '%s\n' 'batch=Verification/Semantics/boolean-expression.batch' 'tests=ShortCircuitFailureProofTests|BooleanBranchLoweringContractTests'
        ;;
    *) echo 'unknown proof family' >&2; exit 64 ;;
esac
