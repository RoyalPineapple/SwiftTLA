.PHONY: build examples core-conformance temporal-symmetry-conformance public-workflow-release-check ci-pr ci-release-qualification

TEMPORAL_SYMMETRY_OUTPUT ?= .build/temporal-symmetry-conformance
build:
	swift build

examples:
	swift test --package-path Examples/SwiftTLADemos
	swift build --package-path Examples/SwiftTLADemoApp

core-conformance:
	./scripts/run_core_conformance.sh --case all --output .build/core-conformance-evidence

temporal-symmetry-conformance:
	./scripts/run_temporal_symmetry_conformance.sh --output $(TEMPORAL_SYMMETRY_OUTPUT)

public-workflow-release-check:
	./scripts/run_public_workflow_support_gate.sh --output .build/public-workflow-support-gate

ci-pr:
	./scripts/run_pr_validation.sh

ci-release-qualification:
	./scripts/run_release_qualification.sh
