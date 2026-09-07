import Testing
@testable import SwiftTLA

@Suite struct NativeFunctionApplicationDomainTests {
    @Test("sequence function application uses one-based keys")
    func sequenceFunctionKeys() throws {
        #expect(try _NativeMachineOperations.sequenceFunctionValue(["first", "second"], at: 1) == "first")
        #expect(try _NativeMachineOperations.sequenceFunctionValue(["first", "second"], at: 2) == "second")
    }

    @Test("sequence function domain errors remain distinct from sequence indexing errors")
    func sequenceFunctionDomainErrors() {
        for index in [Int.min, 0, 3, Int.max] {
            #expect(throws: NativeMachineEvaluationError.tupleIndexOutsideDomain(index)) {
                try _NativeMachineOperations.sequenceFunctionValue([1, 2], at: index)
            }
        }
        #expect(throws: NativeMachineEvaluationError.tupleIndexOutsideDomain(1)) {
            try _NativeMachineOperations.sequenceFunctionValue([Int](), at: 1)
        }
        #expect(throws: NativeMachineEvaluationError.indexOutOfBounds(index: 0, count: 2)) {
            try _NativeMachineOperations.sequenceElement([1, 2], at: 0)
        }
    }
}
