import Testing
@testable import SwiftTLA

struct EnumEncodingTests {
    @Test("mixed formal tags retain nominal identity instead of projecting to a scalar")
    func retainsNominalType() throws {
        let types = try CompiledTypeContext(enums: .init(cases: ["Datum": [
            (name: "model", value: .constant("d1")),
            (name: "text", value: .string("d1_OF_DATUM")),
        ]]), formalNames: [:])
        #expect(types.namedRepresentations["Datum"] == nil)
        #expect(types.canProjectRead(.named("Datum"), to: .named("Datum")))
        #expect(!types.canProjectRead(.named("Datum"), to: .string))
        #expect(!types.canProjectRead(.named("Datum"), to: .modelValue))
        #expect(types.canProjectRead(.finite([.constant("d1")]), to: .named("Datum")))
        #expect(!types.canProjectRead(.finite([.string("d1")]), to: .named("Datum")))
    }

    @Test("generated enum transitions and exports retain model values and strings")
    func preservesFormalTags() throws {
        let authored = SetExpr<String>.literal(Expr(EncodedEnumDomain.Datum.text).assuming(String.self), Expr("é"))
        let exactStrings: Set<TLAValue> = [.string("e\u{301}"), .string("é")]
        #expect(try compiledValue(authored.stateExpr) == .set(exactStrings))
        let scenario = try #require(EncodedEnumDomain.validationScenarios().first)
        let machines = try scenario.initialMachines()
        let token = try #require(TLAStateProjection.Token(validating: "value"))
        let expected: Set<TLAValue> = [.constant("d1"), .constant("d2"), .string("e\u{301}")]
        #expect(EncodedEnumDomain.Datum.first == .second)
        #expect(machines.count == 3)
        #expect(try Set(machines.compactMap { try $0.formalProjection(of: $0.snapshot).value(for: token) }) == expected)
        let initial = try #require(machines.first)
        let states = EncodedEnumDomain.Datum.allCases.map {
            EncodedEnumDomain.State(chosen: 7, value: $0, rawText: initial.state.rawText, texts: initial.state.texts)
        }
        #expect(Set(states).count == 3)
        let actions = EncodedEnumDomain.Datum.allCases.map { EncodedEnumDomain.Action.select(next: $0) }
        #expect(Set(actions).count == 3)
        let rawToken = try #require(TLAStateProjection.Token(validating: "rawText"))
        let textsToken = try #require(TLAStateProjection.Token(validating: "texts"))
        let projection = try initial.formalProjection(of: initial.snapshot)
        #expect(projection.value(for: rawToken) == .string("e\u{301}"))
        #expect(projection.value(for: textsToken) == .set(exactStrings))
        #expect(initial.state.texts.count == 2)
        #expect(try initial.violatedInvariants(checking: [.RawTextPreserved], atLevel: 1).isEmpty)
        #expect(try EncodedEnumDomain.makeMachine(initial.state, configuration: initial.configuration).snapshot == initial.snapshot)
        let changedText = EncodedEnumDomain.State(chosen: initial.state.chosen, value: initial.state.value,
            rawText: "é", texts: initial.state.texts)
        #expect(changedText != initial.state)
        #expect(Set([initial.state, changedText]).count == 2)
        #expect(throws: GeneratedMachineError.invalidInitialState) {
            _ = try EncodedEnumDomain.makeMachine(changedText, configuration: initial.configuration)
        }
        let candidates = try initial.actionCandidates()
        #expect(candidates.count == 3)
        #expect(try Set(candidates.flatMap { try initial.formalCall(for: $0).arguments }) == expected)
        let firstConfiguration = try EncodedEnumDomain.Configuration(nominal: .first)
        let sameConfiguration = try EncodedEnumDomain.Configuration(nominal: .first)
        let secondConfiguration = try EncodedEnumDomain.Configuration(nominal: .second)
        #expect(firstConfiguration == sameConfiguration)
        #expect(firstConfiguration != secondConfiguration)
        #expect(Set([firstConfiguration, sameConfiguration, secondConfiguration]).count == 2)
        #expect(throws: GeneratedMachineStateDiagnostic.self) {
            _ = try EncodedEnumDomain.Configuration(nominal: .text)
        }
        let secondMachines = try EncodedEnumDomain.initialMachines(configuration: secondConfiguration)
        let secondMachine = try #require(secondMachines.first)
        #expect(throws: ExplorationError.configurationMismatch) {
            _ = try ReachabilityGraph(initialMachines: [initial, secondMachine], maximumStates: 3)
        }
        for var machine in machines {
            for value in EncodedEnumDomain.Datum.allCases {
                let after = try machine.send(.select(next: value)).after
                #expect(after.value.rawValue.utf8.elementsEqual(value.rawValue.utf8))
                #expect(try machine.formalProjection(of: machine.snapshot).value(for: token) == value.tlaValue)
                let reached = try machine.formalProjection(of: machine.snapshot)
                #expect(reached.value(for: rawToken) == .string("e\u{301}"))
                #expect(reached.value(for: textsToken) == .set(exactStrings))
                #expect(try machine.violatedInvariants(checking: [.RawTextPreserved], atLevel: 2).isEmpty)
                #expect(EncodedEnumDomain.Datum(formalValue: value.tlaValue)?.tlaValue == value.tlaValue)
            }
        }
        #expect(EncodedEnumDomain.Datum(formalValue: .string("d1")) == nil)
        #expect(EncodedEnumDomain.Datum(formalValue: .constant("e\u{301}")) == nil)
        #expect(EncodedEnumDomain.Datum.text.tlaValue == .string("e\u{301}"))
        #expect(EncodedEnumDomain.Datum.text.tlaValue != .string("é"))
        let graph = try scenario.explore(maximumStates: 3)
        #expect(graph.transitions.count == 3)
        #expect(graph.transitions.values.allSatisfy { $0.count == 3 })
        #expect(graph.safetyViolations.isEmpty)
        let text = try #require(machines.first { $0.state.value.rawValue.utf8.elementsEqual("e\u{301}".utf8) })
        #expect(try text.formalProjection(of: text.snapshot).value(for: token) == .string("e\u{301}"))
        let exactJSON = try TLAJSONStateProjection(validatingJSON: ["chosen": 7, "value": "e\u{301}", "rawText": "e\u{301}", "texts": ["e\u{301}", "é"]])
        let exact = try #require(try text.selectedInitialMachine(from: exactJSON))
        #expect(exact.state.value == .text)
        #expect(exact.state.chosen == 7)
        #expect(try exact.formalProjection(of: exact.snapshot).value(for: token) == .string("e\u{301}"))
        let wrongJSON = try TLAJSONStateProjection(validatingJSON: ["chosen": 7, "value": "é", "rawText": "e\u{301}", "texts": ["e\u{301}", "é"]])
        #expect(try text.selectedInitialMachine(from: wrongJSON) == nil)
        let changedTextJSON = try TLAJSONStateProjection(validatingJSON:
            ["chosen": 7, "value": "e\u{301}", "rawText": "é", "texts": ["e\u{301}", "é"]])
        #expect(try text.selectedInitialMachine(from: changedTextJSON) == nil)
        let missingTextJSON = try TLAJSONStateProjection(validatingJSON:
            ["chosen": 7, "value": "e\u{301}", "rawText": "e\u{301}", "texts": ["é"]])
        #expect(try text.selectedInitialMachine(from: missingTextJSON) == nil)
        let reorderedJSON = try TLAJSONStateProjection(validatingJSON:
            ["chosen": 7, "value": "e\u{301}", "rawText": "e\u{301}", "texts": ["é", "e\u{301}"]])
        #expect(try text.selectedInitialMachine(from: reorderedJSON)?.snapshot == text.snapshot)
        let bundle = try scenario.render().tlaBundle
        #expect(bundle.tla.contains("CONSTANTS d1, d2"))
        #expect(bundle.tla.contains(TLAValue.string("e\u{301}").description))
    }
}
