import Testing
@testable import SwiftTLA
@testable import SwiftTLAPlugin

struct FunctionSpaceMembershipTests {
    @Test("Membership agrees with enumeration for empty, missing, extra, and invalid entries")
    func agreesWithEnumeration() throws {
        let domains: [Set<Int>] = [[], [0], [0, 1]]
        let ranges: [Set<Int>] = [[], [0], [0, 1]]
        let candidates: [[Int: Int]] = [[:], [0: 0], [0: 1], [0: 2], [1: 0], [0: 0, 1: 1], [0: 0, 1: 1, 2: 0]]
        for domain in domains {
            for range in ranges {
                let enumerated = try _NativeMachineOperations.functionSet(domain, range)
                let space = StateExpr.functionSet(.setLiteral(domain.sorted().map { .int($0) }),
                    .setLiteral(range.sorted().map { .int($0) }))
                for candidate in candidates {
                    let value = TLAValue.function(Dictionary(uniqueKeysWithValues: candidate.map {
                        (TLAValue.int($0.key), TLAValue.int($0.value))
                    }))
                    #expect(try compiledValue(.in(.value(value), space)) == .bool(enumerated.contains(candidate)))
                }
            }
        }
    }

    @Test("A representable large space is checked without constructing its members")
    func largeSpace() throws {
        let domain = StateExpr.integerRange(0, 39)
        let member = StateExpr.functionLiteral(domain, "key", 0)
        let membership = StateExpr.in(member, .functionSet(domain, .setLiteral([0, 1])))
        #expect(try compiledValue(membership) == .bool(true))
    }

    @Test("Generated and formal membership avoid expansion and preserve failures")
    func nativeAndFormalAgreement() throws {
        let compilation = try FunctionSpaceMembershipModel.spec.compile()
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: compilation))
        var emitter = NativeSwiftEmitter(model: try MacroCompilation(typeName: "FunctionSpaceMembershipModel", program: program))
        let generated = try emitter.machineMembers().map(\.description).joined(separator: "\n")
        #expect(generated.contains("validateFunctionSetCardinality"))
        try #require(!generated.contains("_NativeMachineOperations.functionSet("))
        let runtime = CompiledRuntime(program: program)
        let initial = try #require(try runtime.initialStates().first)
        let accepted = try #require(compilation.layout.testActionID(named: "accepted"))
        let result = try #require(compilation.layout.testVariableID(named: "result"))
        let successor = try #require(try runtime.successors(for: accepted, from: initial).first)
        var machine = try FunctionSpaceMembershipModel.makeMachine()
        #expect(try machine.send(.accepted).after.result)
        #expect(try successor.state.value(for: result) == .boolean(true))

        let failures: [(String, FunctionSpaceMembershipModel.Action, EvalError, NativeMachineEvaluationError)] = [
            ("candidateFailure", .candidateFailure, .divisionByZero, .divisionByZero)
        ]
        for (name, action, formalError, nativeError) in failures {
            let formalAction = try #require(compilation.layout.testActionID(named: name))
            #expect(throws: formalError) { try runtime.successors(for: formalAction, from: initial) }
            var machine = try FunctionSpaceMembershipModel.makeMachine()
            let before = machine.state
            #expect(throws: nativeError) { try machine.send(action) }
            #expect(machine.state == before)
        }
    }
}
