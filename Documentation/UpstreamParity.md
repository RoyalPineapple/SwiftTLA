# Upstream parity (tlaplus/Examples)

**Rule:** upstream CI-validated specs are the answer key. Port the algorithm; TLC on our `.tlaModule` must match.

## Commands

```bash
make parity                              # TLC every ParityCatalog port
swift run --package-path Examples Examples list
swift run --package-path Examples Examples check allocator/SimpleAllocator
swift run tlc-validate list
swift test --filter UpstreamParity
```

## Green ports (14) — all `matchesUpstreamTLC`

| ID | Distinct |
|----|--------:|
| SpecifyingSystems/HourClock | 12 |
| SpecifyingSystems/HourClock2 | 12 |
| SpecifyingSystems/AsynchInterface | 12 |
| SpecifyingSystems/Channel | 12 |
| DieHard/TypeOK | 16 |
| CoffeeCan/MaxBeanCount5 | 20 |
| transaction_commit/TCommit | 34 |
| Moving_Cat_Puzzle/CatOddBoxes | 30 |
| Moving_Cat_Puzzle/CatEvenBoxes | 48 |
| TeachingConcurrency/Simple_N2 | 13 |
| TeachingConcurrency/Simple_N3 | 51 |
| barriers/Barrier_N6 | 64 |
| CigaretteSmokers/CigaretteSmokers | 6 |
| allocator/SimpleAllocator | 400 |

Source: `Sources/UpstreamParity/ParityCatalog.swift`  
Inventory of all 158 exhaustive-success models: `scripts/parity_registry.json` (69 unique specs)

## Remaining (CI-validated, not yet ported)

Majority, Prisoners, DiningPhilosophers, Bakery-Boulangerie, Paxos*, TwoPhase, ewd*, SpanningTree, ReadersWriters, SingleLaneBridge, GameOfLife, MultiPaxos-SMR, sums_even, Stones, LoopInvariance, LearnProofs, … (see registry).

Port next when language surface allows (or expand fragment). No sketches under those names.

## Layout

| Path | Role |
|------|------|
| `Sources/UpstreamParity/` | All validated ports |
| `Examples/` | CLI over catalog (`list` / `emit` / `check`) — views later |
| `scripts/validate_upstream_parity.sh` | TLC oracle |
| `scripts/parity_registry.json` | Full upstream inventory |

## Definition of done for a port

1. Spec from upstream `.tla` + `.cfg` constants  
2. `ModelChecker` state count == TLC on export == TLC on upstream (safety)  
3. Entry in `ParityCatalog` with `matchesUpstreamTLC: true`  
4. `make parity` green  
