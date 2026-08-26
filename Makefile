.PHONY: build examples finite-graph temporal-symmetry-conformance ci-pr ci-release-qualification

TEMPORAL_SYMMETRY_OUTPUT ?= .build/temporal-symmetry-conformance
build:
	swift build

examples:
	swift test --package-path Examples/SwiftTLADemos
	swift build --package-path Examples/SwiftTLADemoApp

finite-graph:
	./scripts/run_finite_graph_check.sh --case all --output .build/finite-graph-evidence

temporal-symmetry-conformance:
	./scripts/run_temporal_symmetry_conformance.sh --output $(TEMPORAL_SYMMETRY_OUTPUT)

ci-pr:
	./scripts/run_pr_validation.sh

ci-release-qualification:
	./scripts/run_release_qualification.sh
