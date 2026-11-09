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
        let scenario = try #require(EncodedEnumDomain.validationScenarios().first)
        let machines = try scenario.initialMachines()
        let token = try #require(TLAStateProjection.Token(validating: "value"))
        let expected: Set<TLAValue> = [.constant("d1"), .constant("d2"), .string("e\u{301}")]
        #expect(EncodedEnumDomain.Datum.first == .second)
        #expect(machines.count == 3)
        #expect(try Set(machines.compactMap { try $0.formalProjection(of: $0.snapshot).value(for: token) }) == expected)
        let states = EncodedEnumDomain.Datum.allCases.map { EncodedEnumDomain.State(chosen: 7, value: $0) }
        #expect(Set(states).count == 3)
        let actions = EncodedEnumDomain.Datum.allCases.map { EncodedEnumDomain.Action.select(next: $0) }
        #expect(Set(actions).count == 3)
        let initial = try #require(machines.first)
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
        let exactJSON = try TLAJSONStateProjection(validatingJSON: ["chosen": 7, "value": "e\u{301}"])
        let exact = try #require(try text.selectedInitialMachine(from: exactJSON))
        #expect(exact.state.value == .text)
        #expect(exact.state.chosen == 7)
        #expect(try exact.formalProjection(of: exact.snapshot).value(for: token) == .string("e\u{301}"))
        let wrongJSON = try TLAJSONStateProjection(validatingJSON: ["chosen": 7, "value": "é"])
        #expect(try text.selectedInitialMachine(from: wrongJSON) == nil)
        let bundle = try scenario.render().tlaBundle
        #expect(bundle.tla.contains("CONSTANTS d1, d2"))
        #expect(bundle.tla.contains(TLAValue.string("e\u{301}").description))
    }
}
