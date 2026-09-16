import Testing
@testable import SwiftTLA
@testable import SwiftTLAPlugin

struct TemporalConjunctionCompilationTests {
    @Test("nested temporal conjunctions retain their predicates in native code and TLA export")
    func preservesConjunction() throws {
        var spec = canonicalTestSpec(variables: [("value", .value(.int(0)))], actions: [
            ("advance", .assign(.named("value"), .subtract(.int(1), .variable("value"))), [])
        ])
        spec.temporalProperties = [.init(name: "Recurring", expr: .all([
            .alwaysEventually(.equal(.variable("value"), .int(0))),
            .all([.alwaysEventually(.equal(.variable("value"), .int(1)))])
        ]))]
        let compilation = try spec.compile()
        let tla = try compilation.render().tlaBundle.tla
        #expect(tla.contains("Recurring == ([]<>(value = 0) /\\ ([]<>(value = 1)))"))
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: compilation))
        let property = try #require(program.behavior.temporalProperties.first)
        #expect(property.expression.predicates.count == 2)
        var emitter = NativeSwiftEmitter(model: try MacroCompilation(typeName: "Recurring", program: program))
        let generated = try emitter.propertyDeclarations(collectionParameters: "").map(\.description).joined(separator: "\n")
        #expect(generated.contains(".all([.alwaysEventually("))
        #expect(generated.contains("_temporal0_0"))
        #expect(generated.contains("_temporal0_1"))
        #expect(!generated.contains("CompiledEvaluator"))
    }

    @Test("empty temporal conjunction exports true and generates no predicate evaluator")
    func emptyConjunction() throws {
        var spec = canonicalTestSpec(variables: [("value", .value(.int(0)))], actions: [])
        spec.temporalProperties = [.init(name: "Empty", expr: .all([]))]
        let compilation = try spec.compile()
        #expect(try compilation.render().tlaBundle.tla.contains("Empty == TRUE"))
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: compilation))
        var emitter = NativeSwiftEmitter(model: try MacroCompilation(typeName: "Empty", program: program))
        let generated = try emitter.propertyDeclarations(collectionParameters: "").map(\.description).joined(separator: "\n")
        #expect(generated.contains(".all([])"))
        #expect(!generated.contains("private static func _temporal"))
    }
}
