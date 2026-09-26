import Testing
@testable import SwiftTLA

struct MathematicalIntegerDomainTests {
    @Test("Integer domains retain mathematical Int without machine-bound substitutions")
    func configurationExecutionAndExport() throws {
        for values: Set<Int> in [[], [-7, 42], [Int.min, Int.max]] {
            let configuration = try MathematicalIntegerDomainModel.Configuration(Values: values)
            let input = values.sorted()
            var machine = try MathematicalIntegerDomainModel.makeMachine(
                .init(value: Int.min, sequence: input), configuration: configuration)
            #expect(try machine.send(.increment).after.value == Int.min + 1)
            #expect(machine.state.sequence == input)
            #expect(throws: NativeMachineEvaluationError.nonEnumerableIntegerDomain) {
                try MathematicalIntegerDomainModel.initialMachines(configuration: configuration)
            }
            let bundle = try MathematicalIntegerDomainModel.render(configuration: configuration).tlaBundle
            #expect(bundle.tla.contains("ASSUME Values \\in SUBSET Int"))
            #expect(bundle.tla.contains("value \\in Int"))
            #expect(bundle.tla.contains("Seq(Values)"))
            #expect(bundle.tla.contains("Integers"))
        }
    }

    @Test("Integer membership and subsets do not enumerate Int")
    func membershipAndEnumeration() throws {
        for value in [Int.min, -1, 0, 1, Int.max] {
            #expect(try evaluateClosed(Int.all.contains(value).stateExpr) == .bool(true))
        }
        let values = Set<Int>([Int.min, 0, Int.max])
        #expect(try evaluateClosed(Subsets(of: Int.all).contains(values).stateExpr) == .bool(true))
        #expect(try evaluateClosed(values.isSubset(of: Int.all).stateExpr) == .bool(true))
        #expect(try evaluateClosed(Sequences(of: Int.all).contains(values.sorted()).stateExpr) == .bool(true))
        #expect(throws: EvalError.nonEnumerableIntegerDomain) { try evaluateClosed(Int.all.stateExpr) }
    }
}
