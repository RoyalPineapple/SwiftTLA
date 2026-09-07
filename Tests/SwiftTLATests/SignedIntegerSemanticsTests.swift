@testable import SwiftTLA
import Testing

@Suite struct SignedIntegerSemanticsTests {
    @Test("integer division rounds toward negative infinity")
    func floorDivision() throws {
        let cases: [(Int, Int, Int)] = [
            (5, 2, 2), (-5, 2, -3), (5, -2, -3), (-5, -2, 2),
            (-6, 2, -3), (6, -2, -3), (1, -2, -1), (-1, 2, -1),
            (0, -2, 0), (Int.min, 1, Int.min), (Int.max, -1, -Int.max)
        ]
        for (dividend, divisor, expected) in cases {
            #expect(try compiledValue(.divide(.int(dividend), .int(divisor))) == .int(expected))
            #expect(try compiledValue(.integerDivide(.int(dividend), .int(divisor))) == .int(expected))
        }
    }

    @Test("modulo has a nonnegative remainder for positive divisors")
    func nonnegativeRemainders() throws {
        let cases: [(Int, Int, Int)] = [
            (5, 2, 1), (-5, 2, 1), (-6, 2, 0), (0, 2, 0),
            (-1, Int.max, Int.max - 1), (Int.min, Int.max, Int.max - 1)
        ]
        for (dividend, divisor, expected) in cases {
            #expect(try compiledValue(.modulo(.int(dividend), .int(divisor))) == .int(expected))
        }
    }

    @Test("modulo rejects negative divisors before machine-integer remainder")
    func rejectsNegativeDivisors() {
        for divisor in [-1, -2, Int.min] {
            #expect(throws: EvalError.negativeModuloDivisor(divisor)) {
                try compiledValue(.modulo(.int(Int.min), .int(divisor)))
            }
        }
        #expect(throws: EvalError.divisionByZero) {
            try compiledValue(.modulo(.int(1), .int(0)))
        }
    }
}
