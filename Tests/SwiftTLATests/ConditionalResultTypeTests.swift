import Testing
@testable import SwiftTLA

@Suite struct ConditionalResultTypeTests {
    @Test("Computed function conditionals retain the wider branch domain in either order")
    func conditionalDomain() throws {
        for reversed in [false, true] {
            let narrow = StateExpr.variable("selected")
            let wide = StateExpr.variable("stored")
            let body = StateExpr.ifThenElse(.bool(true), reversed ? wide : narrow, reversed ? narrow : wide)
            let lookup = StateExpr.functionApply(.functionLiteral(.setLiteral([.int(1)]), "key", body), .int(1))
            let specification = TLASpec(name: "ConditionalDomain", variables: [
                .init(name: "selected", initialization: .expression(.int(1)), generatedSwiftType: "Node", origin: .compiler),
                .init(name: "stored", initialization: .expression(.int(2)), generatedSwiftType: "OneOf<Node,Missing>", origin: .compiler)
            ], actions: [], invariants: [.init(name: "Result", body: .equal(lookup, wide))])
            let program = try NativeResolvedProgram(compilation: specification.compile(),
                sourceTypes: .init(enums: ["Node": [.int(1)], "Missing": [.int(2)]]))
            let root = try #require(program.invariants.values.first)
            let application = program[program[root].children[0]]
            #expect(application.resultType == .finite([.integer(1), .integer(2)]))
        }
    }
}
