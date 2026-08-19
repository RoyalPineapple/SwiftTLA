#!/usr/bin/env bash
set -euo pipefail

# This suite guards the authored DSL, macro contract, generated runtime, and
# documentation boundary. Release qualification runs the complete test corpus.
# The wrapper takes the repository lock, isolates build artifacts, and bounds
# memory pressure; the filter names only suites compiled into SwiftTLATests.
readonly smoke_filter='SwiftTLATests\.(CanonicalMachineCapabilityTests|GeneratedStateMachineTests|NestedComposableMacroConformanceTests|GeneratedMachineDocumentationTests|RuntimeActionReportTests|SpecParserTests|SymmetricCollectionDeclarationTests|SymmetricCollectionMacroRuntimeTests|SymmetricCollectionPredicateTests|SymmetricCollectionValidationTests)'

exec ./scripts/local-validation.sh swiftpm-test "$smoke_filter"
