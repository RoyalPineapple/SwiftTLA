import Testing
@testable import SwiftTLA
@testable import SwiftTLAPlugin

struct FunctionSpaceMembershipTests {
    @Test("parameter-bound function domains retain every total assignment")
    func configuredDomains() throws {
        let scenarios = try ConfiguredFunctionDomainModel.validationScenarios()
        let expected: [Set<[Int: Int]>] = [[[:]], [[0: 0, 1: 0], [0: 0, 1: 1], [0: 1, 1: 0], [0: 1, 1: 1]]]
        #expect(scenarios.count == expected.count)
        for (scenario, assignments) in zip(scenarios, expected) {
            let machines = try scenario.initialMachines()
            #expect(Set(machines.map { $0.state.values }) == assignments)
            for machine in machines {
                #expect(try machine.successors().first?.machine.state.values == machine.state.values)
            }
            let bundle = try scenario.render().tlaBundle
            #expect(bundle.tla.contains("size"))
            #expect(bundle.tla.contains("->"))
        }
    }

    @Test("function mappings retain configured domains and lexical keys")
    func configuredMappings() throws {
        let scenarios = try ConfiguredFunctionMappingModel.validationScenarios()
        let expected: [[Int: Int]] = [[:], [0: 2, 1: 3]]
        #expect(scenarios.count == expected.count)
        for (scenario, values) in zip(scenarios, expected) {
            let machines = try scenario.initialMachines()
            #expect(machines.count == 1)
            let machine = try #require(machines.first)
            #expect(machine.state.values == values)
            #expect(machine.state.constants == values.mapValues { _ in -1 })
            let successor = try #require(try machine.successors().first)
            #expect(successor.machine.state.values == values)
            #expect(successor.machine.state.constants == machine.state.constants)
            #expect(try scenario.render().tlaBundle.tla.contains("|->"))
        }
    }

    @Test("dictionary projections validate keys, values, and formal identity")
    func validatesDictionaryBoundary() throws {
        let value: [Int: Int] = [0: 1, 1: 0]
        #expect([Int: Int](formalValue: value.tlaValue) == value)
        #expect([Int: Int](formalValue: .function([.string("bad"): .int(1)])) == nil)
        #expect([Int: Int](formalValue: .function([.int(0): .bool(true)])) == nil)
        #expect([Int: Int](formalValue: .int(0)) == nil)
        let colliding: [CollidingFunctionKey: Int] = [.first: 0, .second: 1]
        #expect(colliding.sourceIssue != nil)
    }

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
