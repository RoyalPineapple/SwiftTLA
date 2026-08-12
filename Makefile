.PHONY: test tlc parity build examples core-conformance core-support-gate temporal-symmetry-support-gate temporal-symmetry-release-check ci-local

TEMPORAL_SYMMETRY_OUTPUT ?= .build/temporal-symmetry-support-gate

test:
	swift test

tlc:
	./scripts/setup-tlc.sh
	./scripts/validate_tlc.sh

parity:
	./scripts/setup-tlc.sh
	./scripts/validate_upstream_parity.sh

build:
	swift build

examples:
	swift build --package-path Examples

core-conformance:
	./scripts/run_core_conformance.sh --case all --output .build/core-conformance-evidence

core-support-gate:
	./scripts/run_core_support_gate.sh --output .build/core-support-gate

temporal-symmetry-support-gate:
	./scripts/run_temporal_symmetry_support_gate.sh --output $(TEMPORAL_SYMMETRY_OUTPUT)

temporal-symmetry-release-check:
	./scripts/check_temporal_symmetry_release.sh --output $(TEMPORAL_SYMMETRY_OUTPUT)

ci-local:
	./scripts/run_ci_locally.sh
