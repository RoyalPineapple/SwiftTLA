.PHONY: test tlc parity build examples core-conformance core-support-gate ci-local

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

ci-local:
	./scripts/run_ci_locally.sh
