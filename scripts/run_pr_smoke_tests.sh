#!/usr/bin/env bash
set -euo pipefail

# This suite guards the authored DSL, macro contract, generated runtime, and
# documentation boundary. Release qualification runs the complete test corpus.
readonly smoke_filter='SwiftTLATests\.(CanonicalMachineCapabilityTests|GeneratedStateMachineTests|NestedComposableMacroConformanceTests|GeneratedMachineDocumentationTests|RoundTripFoundationalTests|RuntimeActionOutcomeTests|SpecParserTests|SymmetricCollectionDeclarationTests|SymmetricCollectionMacroRuntimeTests|SymmetricCollectionPredicateTests|SymmetricCollectionValidationTests)'

swift test --filter "$smoke_filter"
