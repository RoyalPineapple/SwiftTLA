import Testing
@testable import SwiftTLA
import SwiftTLAMacros

@TLAModel
private struct RecordFieldExecution {
    enum Step: String, CaseIterable { case advance }
    struct RecordFields {
        let count: Int
        let ready: Bool
    }
    enum Schema: TLARecordSchema {
        typealias Fields = RecordFields
        static func fieldName<Value>(for field: KeyPath<Fields, Value>) -> String? {
            let key = field as AnyKeyPath
            if key == \RecordFields.count { return "count" }
            if key == \RecordFields.ready { return "ready" }
            return nil
        }
        static let count = field(\RecordFields.count)
        static let ready = field(\RecordFields.ready)
        static let fields = [
            TLARecordFieldDeclaration(count, default: 0),
            TLARecordFieldDeclaration(ready, default: false)
        ]
    }
    static var spec: TLASpec {
        #spec("RecordFieldExecution") {
            Algorithm("RecordFieldExecution", scoped: { scope in
                let record = scope.sharedVar("record", initial: Record<Schema>.literal(
                    .init(Schema.count, 0), .init(Schema.ready, false)
                ))
                While(Step.advance, true) {
                    Assign(record, to: record.expr.updating(Schema.count, to: record[Schema.count] + 1))
                }
            })
            // Formal boundary cases cannot name a missing typed schema field.
            SwiftTLA.Action("missing") {
                ActionExpr.assign(.named("record"),
                    StateExpr.variable("record").updated(at: "missing", to: 9)
                )
            }
            SwiftTLA.Action("missingError") {
                ActionExpr.assign(.named("record"),
                    StateExpr.variable("record").updated(at: "missing", to: Expr<Int>(1) / 0)
                )
            }
            SwiftTLA.Action("recordDomain") {
                StateExpr.variable("record").updated(at: "count", to: Expr<Int>(1) / 0).domain.cardinality == 2
            }
        }
    }
}

@Suite("Native record updates preserve the formal relation")
struct NativeRecordUpdateTests {
    @Test("Missing record fields remain unchanged while replacement failures are observed")
    func missingFieldsPreserveDomainAndEvaluateReplacement() throws {
        let compilation = try RecordFieldExecution.spec.compile()
        let runtime = CompiledRuntime(compilation: compilation)
        let initial = try #require(try runtime.initialStates().first)
        let missing = try #require(compilation.layout.testActionID(named: "missing"))
        let successors = try runtime.successors(for: missing, from: initial)
        #expect(successors.map(\.state) == [initial])
        var machine = try RecordFieldExecution.makeMachine()
        let before = machine.state
        _ = try machine.send(.missing)
        #expect(machine.state == before)
        #expect(throws: NativeMachineEvaluationError.divisionByZero) {
            _ = try machine.send(.missingError)
        }
        #expect(machine.state == before)
        #expect(throws: NativeMachineEvaluationError.divisionByZero) {
            _ = try machine.send(.recordDomain)
        }
        #expect(machine.state == before)
    }

    @Test("Updating one heterogeneous record field preserves sibling values")
    func recordFieldUpdateMatchesFormalSuccessors() throws {
        let compilation = try RecordFieldExecution.spec.compile()
        let runtime = CompiledRuntime(compilation: compilation)
        var formal = try #require(try runtime.initialStates().first)
        let action = try #require(compilation.layout.testActionID(named: "advance"))
        let record = try #require(compilation.layout.testVariableID(named: "record"))
        var machine = try RecordFieldExecution.makeMachine()
        for expected in 1...3 {
            let before = machine.state
            let successors = try runtime.successors(for: action, from: formal)
            #expect(successors.count == 1)
            formal = try #require(successors.first).state
            _ = try machine.send(.advance)
            #expect(machine.state.record.count == expected)
            #expect(machine.state.record.ready == before.record.ready)
            #expect(machine.state.record.ready == false)
            #expect(try formal.value(for: record).rendered(using: compilation.layout) == .record([
                "count": .int(machine.state.record.count),
                "ready": .bool(machine.state.record.ready)
            ]))
        }
    }
}

// Formal fixtures isolate evaluation order when more than one operand fails.
@TLAModel
private struct UpdateOperandErrors {
    static var spec: TLASpec {
        TLASpec("UpdateOperandErrors") {
            let result = Var<Int>("result")
            Variable(result, 0)
            SwiftTLA.Action("array") {
                result.becomes(Expr<Int>(
                    StateExpr.tuple([Expr<Int>(1) / 0])
                        .updated(at: 1, to: StateExpr.negate(-9223372036854775808)).at(1)
                ))
            }
            SwiftTLA.Action("function") {
                result.becomes(Expr<Int>(
                    StateExpr.functionLiteral(StateExpr.set([1]), "key", (Expr<Int>(1) / 0).stateExpr)
                        .updated(at: 1, to: StateExpr.negate(-9223372036854775808)).applying(1)
                ))
            }
        }
    }
}

extension NativeRecordUpdateTests {
    @Test("Replacement errors precede failures in the original sequence or function")
    func updateOperandsRetainFormalEvaluationOrder() throws {
        let compilation = try UpdateOperandErrors.spec.compile()
        let runtime = CompiledRuntime(compilation: compilation)
        let initial = try #require(try runtime.initialStates().first)
        let actions: [(name: String, value: UpdateOperandErrors.Action)] = [
            ("array", .array), ("function", .function)
        ]
        for action in actions {
            let formalAction = try #require(compilation.layout.testActionID(named: action.name))
            #expect(throws: EvalError.integerOverflow(.negation, operands: [Int.min])) {
                _ = try runtime.successors(for: formalAction, from: initial)
            }
            var machine = try UpdateOperandErrors.makeMachine()
            let before = machine.state
            #expect(throws: NativeMachineEvaluationError.integerOverflow(.negation, operands: [Int.min])) {
                _ = try machine.send(action.value)
            }
            #expect(machine.state == before)
        }
    }
}
