import SwiftTLA
import Testing

@Suite struct MachineArithmeticSemanticsTests {
    @Test("native arithmetic reports typed overflow and divisor errors")
    func arithmeticErrors() {
        #expect(throws: NativeMachineEvaluationError.integerOverflow(.addition, operands: [Int.max, 1])) {
            try _NativeMachineOperations.add(.max, 1)
        }
        #expect(throws: NativeMachineEvaluationError.integerOverflow(.subtraction, operands: [Int.min, 1])) {
            try _NativeMachineOperations.subtract(.min, 1)
        }
        #expect(throws: NativeMachineEvaluationError.integerOverflow(.multiplication, operands: [Int.max, 2])) {
            try _NativeMachineOperations.multiply(.max, 2)
        }
        #expect(throws: NativeMachineEvaluationError.integerOverflow(.negation, operands: [Int.min])) {
            try _NativeMachineOperations.negate(.min)
        }
        #expect(throws: NativeMachineEvaluationError.integerOverflow(.division, operands: [Int.min, -1])) {
            try _NativeMachineOperations.divide(.min, -1)
        }
        #expect(throws: NativeMachineEvaluationError.divisionByZero) {
            try _NativeMachineOperations.divide(1, 0)
        }
        #expect(throws: NativeMachineEvaluationError.divisionByZero) {
            try _NativeMachineOperations.modulo(1, 0)
        }
        #expect(throws: NativeMachineEvaluationError.negativeModuloDivisor(-1)) {
            try _NativeMachineOperations.modulo(.min, -1)
        }
    }

    @Test("native integer division and modulo retain TLA signed semantics")
    func signedSemantics() throws {
        #expect(try _NativeMachineOperations.divide(-5, 2) == -3)
        #expect(try _NativeMachineOperations.divide(5, -2) == -3)
        #expect(try _NativeMachineOperations.divide(-5, -2) == 2)
        #expect(try _NativeMachineOperations.divide(-6, 2) == -3)
        #expect(try _NativeMachineOperations.divide(.min, 1) == .min)
        #expect(try _NativeMachineOperations.modulo(-5, 2) == 1)
        #expect(try _NativeMachineOperations.modulo(.min, .max) == Int.max - 1)
        #expect(try _NativeMachineOperations.add(.max, 0) == .max)
        #expect(try _NativeMachineOperations.subtract(.min, 0) == .min)
        #expect(try _NativeMachineOperations.multiply(.min, 1) == .min)
        #expect(try _NativeMachineOperations.negate(.max) == -Int.max)
    }

    @Test("summation cancels opposite signs before checking the final bound")
    func cancellationSafeSummation() throws {
        for values in [[Int.max, 1, -1], [1, -1, Int.max], [-1, Int.max, 1]] {
            #expect(try _NativeMachineOperations.sum(values) == .max)
        }
        #expect(try _NativeMachineOperations.sum([Int.min, -1, 1]) == .min)
        #expect(try _NativeMachineOperations.sum([Int.min, Int.max, 1]) == 0)
        #expect(try _NativeMachineOperations.sum([]) == 0)
        #expect(throws: NativeMachineEvaluationError.integerOverflow(.summation, operands: [1, Int.max])) {
            try _NativeMachineOperations.sum([Int.max, 1])
        }
    }
}
