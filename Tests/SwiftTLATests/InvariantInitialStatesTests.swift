import Testing
@testable import SwiftTLA

struct InvariantInitialStatesTests {
    @Test("initial-state selection rejects foreign and duplicate invariant handles")
    func rejectsInvalidSelections() throws {
        let owned = Invariant(_name: "Owned")
        let foreign = Invariant(_name: "Owned")
        let foreignSelection = TLASpec("ForeignSelection") {
            owned { true }
            InitialStates(satisfying: foreign)
        }
        do {
            _ = try foreignSelection.compile()
            Issue.record("A foreign invariant must not select initial states")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.code == .unknownReference)
            #expect(diagnostic.path == "initialStates")
        }

        let duplicateSelection = TLASpec("DuplicateSelection") {
            owned { true }
            InitialStates(satisfying: owned)
            InitialStates(satisfying: owned)
        }
        do {
            _ = try duplicateSelection.compile()
            Issue.record("An initial-state invariant must be selected once")
        } catch let diagnostic as CompilationDiagnostic {
            #expect(diagnostic.code == .duplicateInvariant)
            #expect(diagnostic.path == "initialStates")
        }
    }

    @Test("an invariant selects complete generated and compiled initial states")
    func selectedInitialStates() throws {
        let compilation = try InvariantInitialStatesModel.spec.compile()
        let native = try InvariantInitialStatesModel.initialMachines()
        let nativeStates = try Set(native.map { try $0.formalProjection(of: $0.snapshot) })
        let compiledStates = try Set(CompiledRuntime(compilation: compilation).initialStates().map {
            try $0.projection(using: compilation.layout)
        })

        #expect(nativeStates.count == 8)
        #expect(nativeStates == compiledStates)
        #expect(native.allSatisfy { $0.state.value == 1 })
        #expect(nativeStates.allSatisfy { state in
            guard let pc = TLAStateProjection.Token(validating: "pc"),
                  case .function(let locations) = state.value(for: pc) else { return false }
            return locations[.int(1)] == .string("active")
        })
        #expect(try InvariantInitialStatesModel.render().tlaBundle.tla.contains("/\\ AllowedInitial"))
    }
}
