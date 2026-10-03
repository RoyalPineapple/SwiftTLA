import Foundation
import Testing
import SwiftTLA
import UpstreamParity

struct DieHardestParallelCorpusCheckingTests {
    @Test("Parallel references select the original operators and complete graph comparison")
    func selectsUpstreamOperators() throws {
        let manifest = try JSONDecoder().decode(FiniteGraphManifest.self,
            from: Data(contentsOf: projectURL("Verification/FiniteGraph/cases.json")))
        for (id, name) in [("die-hardest-parallel", "NextParallel"), ("die-hardest-parallel-freeze", "NextParallelFreeze")] {
            let declaration = try #require(manifest.cases.first { $0.id == id })
            #expect(declaration.comparisonMode == .exhaustive)
            #expect(try declaration.resolveScenario()?.name == name)
            let root = projectURL("Verification/FiniteGraph/fixtures")
            let module = try Data(contentsOf: root.appendingPathComponent(declaration.module))
            let configuration = try Data(contentsOf: root.appendingPathComponent(declaration.configuration))
            #expect(SHA256.hex(module) == declaration.moduleSHA256)
            #expect(SHA256.hex(configuration) == declaration.cfgSHA256)
            #expect(String(decoding: configuration, as: UTF8.self).contains("NEXT \(name)\n"))
            #expect(!String(decoding: configuration, as: UTF8.self).contains("CONSTRAINT"))
        }
    }

    @Test("Parallel variants retain every jug transition and freeze only the current behavior", arguments: [false, true])
    func checksCompleteParallelGraph(freeze: Bool) throws {
        let name = freeze ? "NextParallelFreeze" : "NextParallel"
        let scenario = try #require(DieHardestParallelModel.validationScenarios().first { $0.name == name })
        let graph = try scenario.explore(maximumStates: 100_000)
        #expect(graph.initialStates.count == 1)
        func next(_ contents: [String: Int], capacities: [String: Int]) -> Set<[String: Int]> {
            if freeze && contents.values.contains(2) { return [contents] }
            var result: Set<[String: Int]> = []
            for j in capacities.keys {
                var filled = contents
                filled[j] = capacities[j]
                result.insert(filled)
                var emptied = contents
                emptied[j] = 0
                result.insert(emptied)
                for k in capacities.keys where k != j {
                    let amount = min(contents[j]!, capacities[k]! - contents[k]!)
                    var poured = contents
                    poured[j] = contents[j]! - amount
                    poured[k] = contents[k]! + amount
                    result.insert(poured)
                }
            }
            return result
        }
        for (source, transitions) in graph.transitions {
            let state = source.state
            #expect(state.s1 == 0 && state.s2 == 0)
            let expected = Set(next(state.c1, capacities: ["j1": 9, "j2": 10]).flatMap { first in
                next(state.c2, capacities: ["j1": 1, "j2": 3]).map { second in
                    DieHardestParallelModel.State(c1: first, c2: second, s1: 0, s2: 0)
                }
            })
            #expect(Set(transitions.map { $0.target.state }) == expected)
            #expect(transitions.allSatisfy { $0.action == (freeze ? .NextParallelFreeze : .NextParallel) })
        }
        #expect(graph.deadlockedStates.isEmpty)
        guard case .counterexample(let result) = try scenario.check(maximumStates: 100_000) else {
            Issue.record("Both parallel variants must find the source running example's solution")
            return
        }
        #expect(result.trace.count == 7)
        #expect(result.violations == [.invariant(.NotSolved)])
        let final = try #require(result.trace.last).state.state
        #expect(final.c1.values.contains(2) && final.c2.values.contains(2))
        let rendered = try scenario.render()
        #expect(rendered.checkNames == ["NotSolved"])
        #expect(rendered.checksDeadlock)
        #expect(!rendered.tlaBundle.tla.contains("Terminating =="))
        #expect(!rendered.tlaBundle.cfg.contains("CONSTRAINT"))
        #expect(DieHardestParallelModel.spec.sourceAlgorithms.isEmpty)
    }
}
