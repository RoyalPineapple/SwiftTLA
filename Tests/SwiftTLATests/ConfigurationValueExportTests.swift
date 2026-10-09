import Testing
@testable import SwiftTLA

struct ConfigurationValueExportTests {
    @Test("TLC configuration literals retain their direct representation", arguments: [
        TLAValue.int(0), .bool(true), .string("jug"), .constant("Jug"),
        .set([.set([]), .set([.int(3), .int(5)])])])
    func preservesLiterals(_ value: TLAValue) throws {
        let rendered = try render(value)
        #expect(rendered.tlaBundle.cfg.contains("CONSTANT Input = \(value)\n"))
        #expect(!rendered.tlaBundle.tla.contains("__SwiftTLAParameter_0 =="))
    }

    @Test("nonliteral configuration values use collision-free definitions in both exports", arguments: [
        TLAValue.function([:]), .function([.string("small"): .int(3), .string("big"): .int(5)]),
        .tuple([.int(1), .int(2)]), .record(["count": .int(2)]), .int(-1),
        .set([.function([.int(1): .int(2)])]), .string("line\nbreak"), .string("a\"b")])
    func substitutesCompositeValues(_ value: TLAValue) throws {
        let rendered = try render(value)
        let bundles = [rendered.tlaBundle, try rendered.plusCalBundle()]
        for bundle in bundles {
            #expect(bundle.cfg.contains("CONSTANT Input <- __SwiftTLAParameter_0\n"))
            #expect(!bundle.cfg.contains("CONSTANT Input ="))
            #expect(bundle.tla.contains("__SwiftTLAParameter_0 == \(value)\n===="))
        }
    }

    private func render(_ value: TLAValue) throws -> RenderedSpecification {
        let source = """
        ---- MODULE ConfigurationValue ----
        CONSTANT Input
        __SwiftTLAParameter0 == TRUE
        ====

        """
        return try RenderedSpecification(_generatedModule: "ConfigurationValue", source: source,
            compilationIdentity: "configuration-value", declarations: [], checkDeadlock: true,
            invariants: [], reachabilityProperties: [], properties: [], refinements: [], symmetry: [],
            actions: [], _generatedPlusCal: .success(source),
            _generatedParameters: [(name: "Input", value: value)])
    }
}
