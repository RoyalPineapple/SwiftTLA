import Testing
@testable import SwiftTLA
import SwiftTLAMacros

@TLAModel
private struct EscapedRecordSelection {
    struct Fields { let number: Int }
    enum Schema: TLARecordSchema {
        typealias Fields = EscapedRecordSelection.Fields
        static func fieldName<Value>(for field: KeyPath<Fields, Value>) -> String? {
            let key = field as AnyKeyPath
            if key == \Fields.number { return "self" }
            return nil
        }
        static let number = field(\Fields.number)
        static let fields = [TLARecordFieldDeclaration(number, default: 7)]
    }
    static var spec: TLASpec {
        TLASpec("EscapedRecordSelection") {
            let record = Var<Record<Schema>>("record")
            let selector = Var<String>("selector")
            let selected = Var<Int>("selected")
            Variable(record, Record<Schema>.literal(.init(Schema.number, 7)))
            Variable(selector, "self")
            Variable(selected, 0)
            SwiftTLA.Action("fixed") {
                selected.becomes(Expr<Int>(record.stateExpr.applying("self")))
            }
            SwiftTLA.Action("dynamic") {
                selected.becomes(Expr<Int>(record.stateExpr.applying(selector.stateExpr)))
            }
        }
    }
}

@Suite("Native record selectors preserve escaped formal field names")
struct NativeRecordSelectorTests {
    @Test("Fixed and dynamic self selectors read the field rather than the whole record")
    func escapedSelfField() throws {
        let compilation = try EscapedRecordSelection.spec.compile()
        let runtime = CompiledRuntime(compilation: compilation)
        let initial = try #require(try runtime.initialStates().first)
        let selected = try #require(compilation.layout.testVariableID(named: "selected"))
        let cases: [(String, EscapedRecordSelection.Action)] = [("fixed", .fixed), ("dynamic", .dynamic)]
        for (name, action) in cases {
            let formalAction = try #require(compilation.layout.testActionID(named: name))
            let successor = try #require(try runtime.successors(for: formalAction, from: initial).first)
            var machine = try EscapedRecordSelection.makeMachine()
            _ = try machine.send(action)
            #expect(machine.state.selected == 7)
            #expect(try successor.state.value(for: selected) == .integer(machine.state.selected))
        }
    }
}
