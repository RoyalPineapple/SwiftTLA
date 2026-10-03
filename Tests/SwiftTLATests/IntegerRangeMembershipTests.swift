import Testing
@testable import SwiftTLA
@testable import SwiftTLAPlugin

struct IntegerRangeMembershipTests {
    @Test("generated range membership agrees with enumerated ascending and empty domains")
    func agreesWithEnumeration() throws {
        for lower in -3...3 {
            for upper in -3...3 {
                let members = try _NativeMachineOperations.integerRange(lower, upper)
                for value in -4...4 {
                    var machine = try IntegerRangeMembershipModel.makeMachine(
                        configuration: .init(lower: lower, upper: upper, value: value))
                    #expect(try machine.send(.check).after.result == members.contains(value))
                }
            }
        }
    }

    @Test("generated membership retains range bounds instead of allocating every integer")
    func checksLargeRangeWithoutEnumeration() throws {
        let compilation = try IntegerRangeMembershipModel.spec.compile()
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: compilation))
        var emitter = NativeSwiftEmitter(model: try MacroCompilation(typeName: "IntegerRangeMembershipModel", program: program))
        let source = try emitter.machineMembers().map(\.description).joined(separator: "\n")
        try #require(!source.contains("_NativeMachineOperations.integerRange(0, 1000000000)"))
        try #require(source.contains("_NativeMachineOperations.integerRangeBounds(0, 1000000000)"))
        var machine = try IntegerRangeMembershipModel.makeMachine(configuration: .init(lower: 0, upper: 0, value: 4))
        #expect(try machine.send(.large).after.result)
    }

    @Test("range membership preserves cardinality failures and candidate evaluation order")
    func preservesFailures() throws {
        var machine = try IntegerRangeMembershipModel.makeMachine(configuration: .init(lower: 0, upper: 0, value: 0))
        let before = machine.snapshot
        #expect(throws: NativeMachineEvaluationError.collectionCardinalityOverflow(.integerRange, operands: [0, Int.max])) {
            try machine.send(.overflow)
        }
        #expect(machine.snapshot == before)
        for action in [IntegerRangeMembershipModel.Action.candidateFailure, .lowerFailure, .upperFailure, .unionFailure] {
            #expect(throws: NativeMachineEvaluationError.divisionByZero) { try machine.send(action) }
            #expect(machine.snapshot == before)
        }
    }

    @Test("checked range bounds retain integer-limit and empty-range semantics")
    func integerBoundaries() throws {
        #expect(try _NativeMachineOperations.integerRangeBounds(Int.max, Int.min) == nil)
        #expect(try _NativeMachineOperations.integerRangeBounds(Int.min, Int.min + 1) == Int.min...(Int.min + 1))
        #expect(try _NativeMachineOperations.integerRangeBounds(Int.max - 1, Int.max) == (Int.max - 1)...Int.max)
        for lower in [Int.min, 0] {
            #expect(throws: NativeMachineEvaluationError.collectionCardinalityOverflow(.integerRange, operands: [lower, Int.max])) {
                try _NativeMachineOperations.integerRangeBounds(lower, Int.max)
            }
        }
    }
}
