.PHONY: test tlc parity build examples core-conformance

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
