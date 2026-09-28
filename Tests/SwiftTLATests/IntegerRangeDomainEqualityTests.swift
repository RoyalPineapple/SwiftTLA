import Testing
@testable import SwiftTLA
@testable import SwiftTLAPlugin

struct IntegerRangeDomainEqualityTests {
    @Test("generated domain equality agrees with complete, sparse, and empty integer ranges")
    func agreesWithEnumeration() throws {
        let populations: [Set<Int>] = [[], [1, 2], [1, 3]]
        for members in populations {
            for (lower, upper) in [(1, 2), (2, 1), (1, 3), (-1, 1)] {
                let expected = members == (try _NativeMachineOperations.integerRange(lower, upper))
                let configuration = try IntegerRangeDomainEqualityModel.Configuration(
                    members: members, lower: lower, upper: upper)
                var machine = try IntegerRangeDomainEqualityModel.makeMachine(configuration: configuration)
                #expect(try machine.send(.check).after.result == expected)
                machine = try IntegerRangeDomainEqualityModel.makeMachine(configuration: configuration)
                #expect(try machine.send(.reversed).after.result == expected)
            }
        }
    }

    @Test("generated domain equality checks large range bounds without enumeration")
    func largeRangeDoesNotEnumerate() throws {
        let compilation = try IntegerRangeDomainEqualityModel.spec.compile()
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: compilation))
        var emitter = NativeSwiftEmitter(model: try MacroCompilation(
            typeName: "IntegerRangeDomainEqualityModel", program: program))
        let source = try emitter.machineMembers().map(\.description).joined(separator: "\n")
        #expect(source.contains("_NativeMachineOperations.integerRangeBounds(0, 1000000000)"))
        #expect(!source.contains("_NativeMachineOperations.integerRange(0, 1000000000)"))

        var machine = try IntegerRangeDomainEqualityModel.makeMachine(configuration: .init(
            members: [], lower: 1, upper: 2))
        #expect(try !machine.send(.large).after.result)
    }

    @Test("generated domain equality preserves operand failure order")
    func preservesFailureOrder() throws {
        var machine = try IntegerRangeDomainEqualityModel.makeMachine(configuration: .init(
            members: [], lower: 1, upper: 2))
        let before = machine.snapshot
        #expect(throws: NativeMachineEvaluationError.divisionByZero) {
            try machine.send(.domainFirstFailure)
        }
        #expect(machine.snapshot == before)
        #expect(throws: NativeMachineEvaluationError.collectionCardinalityOverflow(
            .integerRange, operands: [0, Int.max])) {
            try machine.send(.rangeFirstFailure)
        }
        #expect(machine.snapshot == before)
    }
}
