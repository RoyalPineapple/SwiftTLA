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
        #expect(Set(machines.map { $0.state.value }) == Set(EncodedEnumDomain.Datum.allCases))
        for var machine in machines {
            for value in EncodedEnumDomain.Datum.allCases {
                #expect(try machine.send(.select(next: value)).after.value == value)
                #expect(EncodedEnumDomain.Datum(formalValue: value.tlaValue) == value)
            }
        }
        #expect(EncodedEnumDomain.Datum(formalValue: .string("d1")) == nil)
        #expect(EncodedEnumDomain.Datum(formalValue: .constant("e\u{301}")) == nil)
        #expect(EncodedEnumDomain.Datum.text.tlaValue == .string("e\u{301}"))
        #expect(EncodedEnumDomain.Datum.text.tlaValue != .string("é"))
        let text = try #require(machines.first { $0.state.value == .text })
        let token = try #require(TLAStateProjection.Token(validating: "value"))
        #expect(try text.formalProjection(of: text.snapshot).value(for: token) == .string("e\u{301}"))
        let bundle = try scenario.render().tlaBundle
        #expect(bundle.tla.contains("CONSTANTS d1, d2"))
        #expect(bundle.tla.contains(TLAValue.string("e\u{301}").description))
        let graph = try scenario.explore(maximumStates: 3)
        #expect(graph.transitions.count == 3)
    }
}
