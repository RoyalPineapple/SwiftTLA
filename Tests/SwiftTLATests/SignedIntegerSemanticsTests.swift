@testable import SwiftTLA
import Testing

@Suite struct SignedIntegerSemanticsTests {
    @Test("large machine integers use small TLA literals in scalar and nested values")
    func largeIntegerRendering() throws {
        let minimum = "((-9 * 1000000000 - 223372036) * 1000000000 - 854775808)"
        let maximum = "((9 * 1000000000 + 223372036) * 1000000000 + 854775807)"
        #expect(TLAValue.int(.min).description == minimum)
        #expect(TLAValue.int(.max).description == maximum)
        #expect(TLAValue.int(2_147_483_648).description == "(2 * 1000000000 + 147483648)")
        #expect(TLAValue.int(-2_147_483_648).description == "(-2 * 1000000000 - 147483648)")
        #expect(TLAValue.tuple([.int(.min), .int(Int.max)]).description == "<<\(minimum), \(maximum)>>")
        #expect(TLAValue.set([.int(.min)]).description == "{\(minimum)}")
        let specification = TLASpec("MinimumIntegerLiteral") {
            Variable(Var<Int>("minimum"), Int.min)
        }
        #expect(try specification.compile().render().tlaBundle.tla.contains("minimum = \(minimum)"))
    }

    @Test("Generated Swift machine uses floor division for negative divisors")
    func generatedSignedDivision() throws {
        var machine = try SignedDivisionOutputModel.makeMachine()
        #expect(machine.state.quotient == 0)
        let transition = try machine.send(.divide)
        #expect(transition.after.quotient == -3)
    }

    @Test("Generated Swift machine uses nonnegative modulo for positive divisors")
    func generatedSignedModulo() throws {
        var machine = try SignedModuloOutputModel.makeMachine()
        let transition = try machine.send(.modulo)
        #expect(transition.after.remainder == 1)
    }

    @Test("Right-first operations preserve the first operand failure")
    func rightOperandFailurePrecedesLeft() {
        let overflow = StateExpr.add(.int(Int.max), .int(1))
        let divisionByZero = StateExpr.divide(.int(1), .int(0))
        let expressions: [StateExpr] = [
            .divide(overflow, divisionByZero),
            .integerDivide(overflow, divisionByZero),
            .modulo(overflow, divisionByZero),
            .in(overflow, .setLiteral([divisionByZero]))
        ]
        for expression in expressions {
            #expect(throws: EvalError.divisionByZero) {
                try compiledValue(expression)
            }
        }
        #expect(throws: EvalError.integerOverflow(.addition, operands: [Int.max, 1])) {
            try compiledValue(.add(overflow, divisionByZero))
        }
    }

    @Test("Generated arithmetic evaluates the right failure before a left overflow")
    func generatedRightOperandFailurePrecedesLeft() throws {
        var machine = try GeneratedArithmeticFailureOrderModel.makeMachine()
        let before = machine.snapshot
        #expect(throws: NativeMachineEvaluationError.divisionByZero) {
            try machine.send(.compute)
        }
        #expect(machine.snapshot == before)

        let rendered = try GeneratedArithmeticFailureOrderModel.render()
        #expect(rendered.intrinsicInvariantNames == Set(["__SwiftTLAEvaluationOK"]))
        let lines = rendered.tlaBundle.root.tla.split(separator: "\n")
        #expect(lines.contains("__SwiftTLADivisionByZeroFailure0 == ~(divisor # 0)"))
        let laterFailures = lines.filter {
            $0.hasPrefix("__SwiftTLAOverflowFailure0 ==")
                || $0.hasPrefix("__SwiftTLAOverflowFailure0_1 ==")
                || $0.hasPrefix("__SwiftTLADivisionByZeroFailure0_1 ==")
                || $0.hasPrefix("__SwiftTLAOverflowFailure0_2 ==")
        }
        #expect(laterFailures.count == 4)
        #expect(laterFailures.allSatisfy { $0.contains("== (IF divisor # 0 THEN") })
        #expect(lines.contains("__SwiftTLAEvaluationOK == ~(__SwiftTLADivisionByZeroFailure0) /\\ ~(__SwiftTLAOverflowFailure0) /\\ ~(__SwiftTLAOverflowFailure0_1) /\\ ~(__SwiftTLADivisionByZeroFailure0_1) /\\ ~(__SwiftTLAOverflowFailure0_2)"))
        #expect(lines.contains { $0.hasPrefix("compute == (IF (IF divisor # 0 THEN") })
    }

    @Test("Generated modulo rejects a negative divisor on both checking paths")
    func generatedNegativeModuloFailure() throws {
        var machine = try GeneratedNegativeModuloFailureModel.makeMachine()
        let before = machine.snapshot
        #expect(throws: NativeMachineEvaluationError.negativeModuloDivisor(-1)) {
            try machine.send(.compute)
        }
        #expect(machine.snapshot == before)

        let rendered = try GeneratedNegativeModuloFailureModel.render()
        #expect(rendered.intrinsicInvariantNames == Set(["__SwiftTLAEvaluationOK"]))
        let lines = rendered.tlaBundle.root.tla.split(separator: "\n")
        #expect(lines.contains("__SwiftTLADivisionByZeroFailure0 == ~(divisor # 0)"))
        #expect(lines.contains("__SwiftTLANegativeModuloDivisorFailure0 == (IF divisor # 0 THEN ~(divisor > 0) ELSE FALSE)"))
        #expect(lines.contains("__SwiftTLAEvaluationOK == ~(__SwiftTLADivisionByZeroFailure0) /\\ ~(__SwiftTLANegativeModuloDivisorFailure0)"))
        #expect(lines.contains { $0.hasPrefix("compute == (IF (IF divisor # 0 THEN (IF divisor > 0 THEN") })
    }

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
            for operation in [CompiledOperation.divide, .integerDivide] {
                var stack: [CompiledValue] = [.boolean(true), .integer(divisor), .integer(dividend)]
                try operation.apply(to: &stack, operandCount: 2)
                #expect(stack == [.boolean(true), .integer(expected)])
            }
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
            var stack: [CompiledValue] = [.boolean(true), .integer(divisor), .integer(dividend)]
            try CompiledOperation.modulo.apply(to: &stack, operandCount: 2)
            #expect(stack == [.boolean(true), .integer(expected)])
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
