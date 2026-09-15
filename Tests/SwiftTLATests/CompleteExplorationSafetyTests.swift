import Testing
@testable import SwiftTLA

struct CompleteExplorationSafetyTests {
    @Test("violations retain separate witnesses without truncating any initial branch")
    func preservesGraphAndAllSafetyChecks() throws {
        let value = Var<Int>("value")
        let specification = TLASpec("CompleteSafety") {
            Variable(value, in: [0, 10])
            Action("advance") { value.becomes(value + 1).when(value >= 10 && value < 13) }
            Invariant("BelowEleven") { value < 11 }
            Invariant("BelowThirteen") { value < 13 }
        }
        let compilation = try specification.compile()
        let checker = ModelChecker(compilation: compilation,
            configuration: try .init(maximumStateLimit: 10, symmetryReduction: .disabled))
        let exploration = try checker.explore()
        #expect(exploration.isComplete)
        #expect(exploration.initialStateIDs.count == 2)
        #expect(exploration.graph.states.count == 5)
        #expect(exploration.graph.transitions.values.reduce(0) { $0 + $1.count } == 3)
        #expect(exploration.safetyViolations.count == 3)
        #expect(Set(exploration.safetyViolations.compactMap { $0.diagnostic?.subject })
            == ["BelowEleven", "BelowThirteen"])
        #expect(exploration.safetyViolations.first?.diagnostic?.kind == .deadlock)
        #expect(try checker.check().diagnostic?.subject == "BelowEleven")
        try exploration.validate(for: compilation)

        let bounded = try ModelChecker(compilation: compilation,
            configuration: .init(maximumStateLimit: 4, symmetryReduction: .disabled)).explore()
        #expect(!bounded.isComplete)
        #expect(bounded.completion.diagnostic?.kind == .stateLimit)
        #expect(Set(bounded.safetyViolations.compactMap { $0.diagnostic?.subject }) == ["BelowEleven"])
        #expect(bounded.safetyViolations.contains { $0.diagnostic?.kind == .deadlock })
    }
}
