import Testing
@testable import SwiftTLA

struct ConfigurationValueExportTests {
    @Test("TLC configuration literals retain their direct representation", arguments: [
        (TLAValue.int(0), "0"), (.int(1_000_000_000), "1000000000"), (.bool(true), "TRUE"),
        (.string("jug"), #""jug""#), (.constant("Jug"), "Jug"), (.set([.constant("Jug")]), "{Jug}"),
        (.set([.set([]), .set([.int(3), .int(5)])]), "{{3, 5}, {}}")])
    func preservesLiterals(_ input: (value: TLAValue, expression: String)) throws {
        let rendered = try render(input.value)
        #expect(rendered.tlaBundle.cfg.contains("CONSTANT Input = \(input.expression)\n"))
        #expect(!rendered.tlaBundle.tla.contains("__SwiftTLAParameter__0 =="))
    }

    @Test("a configuration-only encoded string opts into decoded TLC evidence")
    func encodedConfigurationString() throws {
        let bundle = try render(.string("é")).tlaBundle
        #expect(!bundle.tla.contains(FormalStringEncoding.declaration))
        #expect(bundle.cfg.contains(#""__SwiftTLA_UTF8_V1__C3A9""#))
        #expect(bundle.usesFormalStringEncoding)

        let unmarkedExternal = TLAModuleBundle.external(root: .init(
            name: bundle.root.name, tla: bundle.tla, cfg: bundle.cfg))
        #expect(!unmarkedExternal.usesFormalStringEncoding)
    }

    @Test("nonliteral configuration values use collision-free definitions in both exports", arguments: [
        (TLAValue.function([:]), #"[__tla_fn_0 \in {} |-> TRUE]"#),
        (.function([.string("small"): .int(3), .string("big"): .int(5)]),
         #"[__tla_fn_0 \in {"big", "small"} |-> CASE (__tla_fn_0 = "big") -> 5 [] (__tla_fn_0 = "small") -> 3]"#),
        (.tuple([.int(1), .int(2)]), "<<1, 2>>"), (.tuple([.constant("Jug")]), "<<JugAlias>>"),
        (.record(["count": .int(2)]), "[count |-> 2]"),
        (.record(["Jug": .constant("Jug")]), "[Jug |-> JugAlias]"),
        (.function([.constant("Jug"): .constant("Jug")]), #"[__tla_fn_0 \in {JugAlias} |-> JugAlias]"#),
        (.set([.tuple([.constant("Jug")])]), "{<<JugAlias>>}"), (.int(-1), "-1"),
        (.int(1_000_000_001), "(1 * 1000000000 + 1)"),
        (.int(Int(Int32.max)), "(2 * 1000000000 + 147483647)"),
        (.set([.int(1_000_000_001)]), "{(1 * 1000000000 + 1)}"),
        (.set([.function([.int(1): .int(2)])]), #"{[__tla_fn_0 \in {1} |-> 2]}"#),
        (.string("line\nbreak"), #""line\nbreak""#), (.string("a\"b"), #""a\"b""#),
        (.string("__SwiftTLAParameter__0\""), #""__SwiftTLAParameter__0\"""#)])
    func substitutesCompositeValues(_ input: (value: TLAValue, expression: String)) throws {
        for closedConstant in [false, true] {
            let rendered = try render(input.value, closedConstant: closedConstant)
            let selected = try rendered.selectingChecks(ModelChecks<String>(properties: []),
                formalPropertyNames: [:], fairnessProfile: "Profile")
            let bundles = [rendered.tlaBundle, try rendered.plusCalBundle(), try selected.plusCalBundle()]
            for bundle in bundles {
                #expect(bundle.cfg.contains("CONSTANT Input <- __SwiftTLAParameter__0\n"))
                #expect(!bundle.cfg.contains("CONSTANT Input ="))
                #expect(bundle.tla.contains("__SwiftTLAParameter__0 == \(input.expression)\n===="))
            }
        }
    }

    private func render(_ value: TLAValue, closedConstant: Bool = false) throws -> RenderedSpecification {
        let source = """
        ---- MODULE ConfigurationValue ----
        CONSTANTS Input, JugAlias
        __SwiftTLAParameter0 == TRUE
        Spec == TRUE
        ProfileSpec == TRUE
        ====

        """
        return try RenderedSpecification(_generatedModule: "ConfigurationValue", source: source,
            compilationIdentity: "configuration-value",
            declarations: ["CONSTANT JugAlias = Jug"] + (closedConstant ? ["CONSTANT Input = \(value)"] : []),
            _generatedConstants: closedConstant ? [ConstantDecl("Input", value)] : [], checkDeadlock: true,
            _generatedIntegerBitWidth: Int.bitWidth,
            _generatedIntrinsicInvariants: [],
            invariants: [], reachabilityProperties: [], properties: [], refinements: [], symmetry: [],
            actions: [], _generatedPlusCal: .success(source),
            _generatedPlusCalProfiles: ["Profile": .success(source.replacingOccurrences(
                of: "__SwiftTLAParameter0 == TRUE", with: "__SwiftTLAParameter_0 == TRUE"))],
            _generatedParameters: closedConstant ? [] : [(name: "Input", value: value)],
            _generatedFairnessProfileOperators: ["Profile": "ProfileSpec"])
    }
}
