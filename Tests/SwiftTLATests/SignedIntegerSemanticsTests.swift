import Foundation
@testable import SwiftTLA
@testable import SwiftTLAPlugin
import SwiftParser
import SwiftSyntax
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

    @Test("Generated Swift retains raw and formal signed division")
    func generatedSignedDivision() throws {
        let compilation = try SignedDivisionOutputModel.spec.compile()
        let runtime = CompiledRuntime(compilation: compilation)
        let initial = try #require(try runtime.initialStates().first)
        let quotient = try #require(compilation.layout.variables.first { $0.declaration.name == "quotient" }).id
        let cases: [(SignedDivisionOutputModel.Action, String, Int)] = [
            (.divide, "divide", -2), (.formalDivide, "formalDivide", -3),
            (.integerDivide, "integerDivide", -3),
            (.formalLocal, "formalLocal", -3),
            (.rawLocal, "rawLocal", -2),
        ]
        for (step, label, expected) in cases {
            let action = try #require(compilation.layout.testActionID(named: label))
            let successor = try #require(try runtime.successors(for: action, from: initial).first)
            #expect(try successor.state.value(for: quotient) == .integer(expected), "Runtime \(label)")
            var machine = try SignedDivisionOutputModel.makeMachine()
            #expect(machine.state.quotient == 0)
            let transition = try machine.send(step)
            #expect(transition.after.quotient == expected, "Native \(label)")
        }
        let failures: [(SignedDivisionOutputModel.Action, String, NativeMachineEvaluationError, EvalError)] = [
            (.zeroDivide, "zeroDivide", .divisionByZero, .divisionByZero),
            (.overflowDivide, "overflowDivide", .integerOverflow(.division, operands: [Int.min, -1]),
                .integerOverflow(.division, operands: [Int.min, -1])),
        ]
        for (step, label, nativeFailure, runtimeFailure) in failures {
            var machine = try SignedDivisionOutputModel.makeMachine()
            let before = machine.snapshot
            #expect(throws: nativeFailure) { try machine.send(step) }
            #expect(machine.snapshot == before)
            let action = try #require(compilation.layout.testActionID(named: label))
            #expect(throws: runtimeFailure) { try runtime.successors(for: action, from: initial) }
        }

        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: compilation))
        let formalID = try #require(compilation.layout.testActionID(named: "formalDivide"))
        let formalAction = try #require(program.behavior.actions.first { $0.id == formalID })
        var emitter = NativeSwiftEmitter(model: try MacroCompilation(
            typeName: "SignedDivisionOutputModel", program: program))
        let native = try emitter.updateFunction(formalAction, configurationParameters: "")
        let writes = try emitter.actionFunctions(formalAction.body).writes
        try verifyGeneratedActionWriteOutput(native, action: formalAction.body,
            program: program, stateFields: emitter.stateMemberNames, parts: writes)
        let call = "SwiftTLA._NativeMachineOperations.divide(5, -2)"
        try #require(native.description.components(separatedBy: call).count == 2)
        for (label, changedCall) in [
            ("operand", "SwiftTLA._NativeMachineOperations.divide(4, -2)"),
            ("order", "SwiftTLA._NativeMachineOperations.divide(-2, 5)"),
            ("operation", "SwiftTLA._NativeMachineOperations.modulo(5, -2)"),
            ("qualification", "_NativeMachineOperations.divide(5, -2)"),
        ] {
            let changed = native.description.replacingOccurrences(of: call, with: changedCall)
            let declaration = try #require(Parser.parse(source: changed).statements.first?.item.as(DeclSyntax.self))
            do {
                try verifyGeneratedActionWriteOutput(declaration, action: formalAction.body,
                    program: program, stateFields: emitter.stateMemberNames, parts: writes)
                Issue.record("Literal division native corruption accepted: \(label)")
            } catch let diagnostic as CompilationDiagnostic {
                #expect(diagnostic.path.hasPrefix("native.action.binding."))
            }
        }
        let output = try program.renderModule()
        let invariant = try #require(output.configuration.intrinsicInvariants.first {
            $0.hasPrefix("__SwiftTLAEvaluationOK")
        })
        let renderer = CompiledTLARenderer(moduleName: program.moduleName, reservedNames: [],
            layout: program.layout, bindings: .init(binders: program.binderNames),
            operators: compilation.semantics.operators,
            actions: program.behavior.actions, functions: program.functions)
        func verifyFailureOutput(_ module: String, declarations: [String]) throws {
            try StraightLineRenderedActionCheck.verifyEvaluationSelection(program.behavior,
                module: module, failureDeclarations: declarations, evaluationInvariant: invariant,
                configuration: output.configuration, renderer: renderer)
        }
        try verifyFailureOutput(output.renderedModuleSource, declarations: output.evaluationFailureDeclarations)
        let zeroID = try #require(compilation.layout.testActionID(named: "zeroDivide"))
        let overflowID = try #require(compilation.layout.testActionID(named: "overflowDivide"))
        let operandsBase = "__SwiftTLAOverflowOperands\(overflowID.ordinal)"
        let operands = try #require(output.evaluationFailureDeclarations.first {
            $0.hasPrefix(operandsBase + " == ")
        }).components(separatedBy: " == ")
        try #require(operands.count == 2 && operands[1].hasPrefix("<<") && operands[1].hasSuffix(">>"))
        let pair = String(operands[1].dropFirst(2).dropLast(2)).components(separatedBy: ", ")
        try #require(pair.count == 2 && pair[0] != pair[1])
        for (label, base, wrongValue) in [
            ("detail", "__SwiftTLADivisionByZeroFailure\(zeroID.ordinal)", "FALSE"),
            ("operation", "__SwiftTLAOverflowOperation\(overflowID.ordinal)", "\"addition\""),
            ("operands", operandsBase, "<<\(pair[1]), \(pair[0])>>"),
        ] {
            let original = try #require(output.evaluationFailureDeclarations.first {
                $0.hasPrefix(base + " == ")
            })
            let changed = base + " == " + wrongValue
            try #require(changed != original)
            try #require(output.renderedModuleSource.components(separatedBy: original).count == 2)
            let changedModule = output.renderedModuleSource.replacingOccurrences(of: original, with: changed)
            do {
                try verifyFailureOutput(changedModule,
                    declarations: output.evaluationFailureDeclarations.map { $0 == original ? changed : $0 })
                Issue.record("Signed division emitted TLA failure \(label) escaped output verification")
            } catch let diagnostic as CompilationDiagnostic {
                #expect(diagnostic.path == "tla.evaluationSelection")
            }
        }
    }

    @Test("Generated Swift machine uses nonnegative modulo for positive divisors")
    func generatedSignedModulo() throws {
        let compilation = try SignedModuloOutputModel.spec.compile()
        let runtime = CompiledRuntime(compilation: compilation)
        let initial = try #require(try runtime.initialStates().first)
        let remainder = try #require(compilation.layout.variables.first { $0.declaration.name == "remainder" }).id
        let cases: [(SignedModuloOutputModel.Action, String)] = [(.modulo, "modulo"), (.literalModulo, "literalModulo")]
        for (step, label) in cases {
            var machine = try SignedModuloOutputModel.makeMachine()
            let transition = try machine.send(step)
            #expect(transition.after.remainder == 1)
            let action = try #require(compilation.layout.testActionID(named: label))
            let successor = try #require(try runtime.successors(for: action, from: initial).first)
            #expect(try successor.state.value(for: remainder) == .integer(1))
        }
        let failures: [(SignedModuloOutputModel.Action, String, NativeMachineEvaluationError, EvalError)] = [
            (.negativeModulo, "negativeModulo", .negativeModuloDivisor(-2), .negativeModuloDivisor(-2)),
            (.zeroModulo, "zeroModulo", .divisionByZero, .divisionByZero),
        ]
        for (step, label, nativeFailure, runtimeFailure) in failures {
            var machine = try SignedModuloOutputModel.makeMachine()
            let before = machine.snapshot
            #expect(throws: nativeFailure) { try machine.send(step) }
            #expect(machine.snapshot == before)
            let action = try #require(compilation.layout.testActionID(named: label))
            #expect(throws: runtimeFailure) { try runtime.successors(for: action, from: initial) }
        }
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
        #expect(lines.contains { $0.contains("(IF divisor # -1 THEN TRUE ELSE") })
        let laterFailures = lines.filter {
            $0.hasPrefix("__SwiftTLAOverflowFailure0 ==")
                || $0.hasPrefix("__SwiftTLAOverflowFailure0_1 ==")
                || $0.hasPrefix("__SwiftTLADivisionByZeroFailure0_1 ==")
                || $0.hasPrefix("__SwiftTLAOverflowFailure0_2 ==")
        }
        #expect(laterFailures.count == 4)
        #expect(laterFailures.allSatisfy { $0.contains("== (IF divisor # 0 THEN") })
        #expect(lines.contains { $0.hasPrefix("__SwiftTLAAnyEvaluationFailure0 ==") && $0.contains("divisor # 0") })
        #expect(lines.contains("__SwiftTLAEvaluationOK == ~(__SwiftTLAAnyEvaluationFailure0)"))
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
        #expect(lines.contains { $0.hasPrefix("__SwiftTLAAnyEvaluationFailure0 ==") && $0.contains("divisor > 0") })
        #expect(lines.contains("__SwiftTLAEvaluationOK == ~(__SwiftTLAAnyEvaluationFailure0)"))
        #expect(lines.contains { $0.hasPrefix("compute == (IF (IF divisor # 0 THEN (IF divisor > 0 THEN") })
    }

    @Test("Only the selected conditional branch reports an arithmetic failure")
    func generatedConditionalArithmeticFailure() throws {
        let machines = try GeneratedConditionalArithmeticFailureModel.initialMachines()
        #expect(machines.count == 4)
        for var machine in machines {
            let before = machine.snapshot
            let attempt = machine.state.attempt
            if machine.state.attempt == (machine.state.divisor == 0) {
                #expect(throws: NativeMachineEvaluationError.divisionByZero) {
                    try machine.send(.compute)
                }
                #expect(machine.snapshot == before)
            } else {
                _ = try machine.send(.compute)
                #expect(machine.state.result == (attempt ? -1 : 1))
            }
        }

        let rendered = try GeneratedConditionalArithmeticFailureModel.render()
        #expect(rendered.intrinsicInvariantNames == Set(["__SwiftTLAEvaluationOK"]))
        let lines = rendered.tlaBundle.root.tla.split(separator: "\n")
        #expect(lines.contains { $0.hasPrefix("compute ==") && $0.contains("divisor # 0") })
        #expect(lines.contains { $0.hasPrefix("__SwiftTLADivisionByZeroFailure0 ==") && $0.contains("IF attempt THEN") })
        #expect(lines.contains { $0.hasPrefix("__SwiftTLADivisionByZeroFailure0_1 ==") && $0.contains("IF attempt THEN FALSE ELSE") })
    }

    @Test("A membership condition reports failure only in its selected branch")
    func generatedMembershipConditionalFailure() throws {
        let machines = try GeneratedMembershipConditionalFailureModel.initialMachines()
        #expect(machines.count == 2)
        for var machine in machines {
            let before = machine.snapshot
            if machine.state.member == 1 {
                #expect(throws: NativeMachineEvaluationError.divisionByZero) {
                    try machine.send(.compute)
                }
                #expect(machine.snapshot == before)
            } else {
                _ = try machine.send(.compute)
                #expect(machine.state.result == 1)
            }
        }

        let rendered = try GeneratedMembershipConditionalFailureModel.render()
        #expect(rendered.intrinsicInvariantNames == Set(["__SwiftTLAEvaluationOK"]))
        let lines = rendered.tlaBundle.root.tla.split(separator: "\n")
        #expect(lines.contains { $0.hasPrefix("compute ==") && $0.contains("member \\in {1}") })
        #expect(lines.contains {
            $0.hasPrefix("__SwiftTLADivisionByZeroFailure0 ==")
                && $0.contains("IF (member \\in {1}) THEN") && $0.contains("divisor # 0")
        })
        #expect(lines.contains {
            $0 == "__SwiftTLAEvaluationOK == ~(__SwiftTLAAnyEvaluationFailure0)"
        })
        #expect(lines.contains { $0.hasPrefix("__SwiftTLAAnyEvaluationFailure0 ==") && $0.contains("member \\in {1}") })
    }

    @Test("A conditional reports condition failure before either branch")
    func generatedFallibleConditionFailureOrder() throws {
        let machines = try GeneratedFallibleConditionModel.initialMachines()
        #expect(machines.count == 4)
        for var machine in machines {
            let before = machine.snapshot
            switch machine.state.divisor {
            case Int.max:
                #expect(throws: NativeMachineEvaluationError.integerOverflow(.addition, operands: [Int.max, 1])) {
                    try machine.send(.compute)
                }
                #expect(machine.snapshot == before)
            case 0, -2:
                #expect(throws: NativeMachineEvaluationError.divisionByZero) {
                    try machine.send(.compute)
                }
                #expect(machine.snapshot == before)
            case -3:
                _ = try machine.send(.compute)
                #expect(machine.state.result == -1)
            default:
                Issue.record("unexpected initial divisor")
            }
        }

        let rendered = try GeneratedFallibleConditionModel.render()
        #expect(rendered.intrinsicInvariantNames == Set(["__SwiftTLAEvaluationOK"]))
        let lines = rendered.tlaBundle.root.tla.split(separator: "\n")
        let compute = try #require(lines.first { $0.hasPrefix("compute ==") })
        #expect(compute.contains("THEN (IF ((divisor + 1) > 0)"))
        #expect(compute.hasSuffix("ELSE FALSE)"))
        #expect(lines.contains { $0.hasPrefix("__SwiftTLAOverflowFailure0 ==") })
        #expect(lines.contains { $0.hasPrefix("__SwiftTLADivisionByZeroFailure0 ==") && $0.contains("THEN (IF ((divisor + 1) > 0) THEN") })
        #expect(lines.contains { $0.hasPrefix("__SwiftTLADivisionByZeroFailure0_1 ==") && $0.contains("THEN FALSE ELSE") })
    }

    @Test("Membership checks its set before an overflowing member on both outputs")
    func generatedMembershipFailureOrder() throws {
        let compilation = try GeneratedMembershipFailureOrderModel.spec.compile()
        let initial = try firstCompiledState(in: compilation)
        #expect(throws: EvalError.divisionByZero) {
            try compiledSuccessors(named: "compute", arguments: [], in: compilation, from: initial)
        }

        var machine = try GeneratedMembershipFailureOrderModel.makeMachine()
        let before = machine.snapshot
        #expect(throws: NativeMachineEvaluationError.divisionByZero) {
            try machine.send(.compute)
        }
        #expect(machine.snapshot == before)

        let rendered = try GeneratedMembershipFailureOrderModel.render()
        #expect(rendered.intrinsicInvariantNames == Set(["__SwiftTLAEvaluationOK"]))
        let lines = rendered.tlaBundle.root.tla.split(separator: "\n")
        #expect(lines.contains("__SwiftTLADivisionByZeroFailure0 == ~(divisor # 0)"))
        #expect(lines.contains { $0.hasPrefix("__SwiftTLAOverflowFailure0 == (IF divisor # 0 THEN") })
        #expect(lines.contains { $0.hasPrefix("compute == (IF (IF divisor # 0 THEN") })
    }

    @Test("Tuple elements preserve the first arithmetic failure on both outputs")
    func generatedTupleFailureOrder() throws {
        var machine = try GeneratedTupleFailureOrderModel.makeMachine()
        let before = machine.snapshot
        #expect(throws: NativeMachineEvaluationError.divisionByZero) {
            try machine.send(.compute)
        }
        #expect(machine.snapshot == before)

        let rendered = try GeneratedTupleFailureOrderModel.render()
        #expect(rendered.intrinsicInvariantNames == Set(["__SwiftTLAEvaluationOK"]))
        let lines = rendered.tlaBundle.root.tla.split(separator: "\n")
        #expect(lines.contains("__SwiftTLADivisionByZeroFailure0 == ~(divisor # 0)"))
        #expect(lines.contains { $0.hasPrefix("__SwiftTLAOverflowFailure0 == (IF divisor # 0 THEN") })
        #expect(lines.contains { $0.hasPrefix("compute == (IF (IF divisor # 0 THEN") })

        var overflowMachine = try GeneratedTupleFailureOrderModel.makeMachine()
        #expect(throws: NativeMachineEvaluationError.integerOverflow(.addition,
            operands: [Int.max, 1])) {
            try overflowMachine.send(.overflow)
        }
        #expect(lines.contains { $0.hasPrefix("overflow == (IF ") })
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
