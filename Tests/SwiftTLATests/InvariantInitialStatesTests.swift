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

    @Test("an invariant selects every valid generated initial combination")
    func selectedInitialStates() throws {
        let native = try InvariantInitialStatesModel.initialMachines()
        let nativeStates = try Set(native.map { try $0.formalProjection(of: $0.snapshot) })
        #expect(nativeStates.count == 8)
        #expect(native.allSatisfy { $0.state.value == 1 })
        let pc = try #require(TLAStateProjection.Token(validating: "pc"))
        let choice = try #require(TLAStateProjection.Token(validating: "choice"))
        let combinations = try Set(nativeStates.map { state -> [TLAValue] in
            guard case .function(let locations) = try #require(state.value(for: pc)),
                  case .function(let choices) = try #require(state.value(for: choice)) else {
                throw TLAStateProjectionDiagnostic.invalidValue(path: "pc or choice")
            }
            #expect(locations[.int(1)] == .string("active"))
            return [try #require(choices[.int(1)]), try #require(choices[.int(2)]),
                try #require(locations[.int(2)])]
        })
        let bits: [TLAValue] = [.int(0), .int(1)]
        let locations: [TLAValue] = [.string("idle"), .string("active")]
        let expected = Set(bits.flatMap { first in
            bits.flatMap { second in locations.map { location in [first, second, location] } }
        })
        #expect(combinations == expected)
        #expect(try InvariantInitialStatesModel.render().tlaBundle.tla.contains("/\\ AllowedInitial"))
    }
}
