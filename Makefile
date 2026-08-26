.PHONY: finite-graph temporal-symmetry-conformance

TEMPORAL_SYMMETRY_OUTPUT ?= .build/temporal-symmetry-conformance
finite-graph:
	./scripts/run_finite_graph_check.sh --case all --output .build/finite-graph-evidence

temporal-symmetry-conformance:
	./scripts/run_temporal_symmetry_conformance.sh --output $(TEMPORAL_SYMMETRY_OUTPUT)
