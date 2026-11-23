import SwiftDiagnostics
import SwiftSyntax

struct StateCopySyntax {
    enum Source {
        case field(TokenSyntax)
        case integer(Int)
    }

    struct FieldAssignment {
        let target: TokenSyntax
        let adds: Bool
        let source: Source
    }

    struct Problem: Error, DiagnosticMessage {
        let node: Syntax
        let message: String
        let severity = DiagnosticSeverity.error
        let diagnosticID = MessageID(domain: "SwiftTLA", id: "state-copy")
    }

    static func matches(_ call: FunctionCallExprSyntax) -> Bool {
        call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "Do"
            && call.arguments.contains { $0.label?.text == "in" }
    }

    static func fields(in call: FunctionCallExprSyntax) throws(Problem) -> [FieldAssignment] {
        let labels = call.arguments.map { $0.label?.text }
        guard labels == [nil, "in"] || labels == [nil, "when", "in"],
              let metatype = call.arguments.last?.expression.as(MemberAccessExprSyntax.self),
              metatype.declName.baseName.text == "self",
              metatype.base?.as(DeclReferenceExprSyntax.self)?.baseName.text == "State",
              call.additionalTrailingClosures.isEmpty, let closure = call.trailingClosure,
              let signature = closure.signature, signature.capture == nil, signature.attributes.isEmpty,
              signature.effectSpecifiers == nil, signature.returnClause == nil,
              case .simpleInput(let parameters) = signature.parameterClause, parameters.count == 1,
              let binder = parameters.first?.name.sourceIdentifierName, binder != "_" else {
            throw Problem(node: Syntax(call), message: "Use Do(Step.copy, in: State.self) { state in … } with one named state parameter.")
        }
        func field(_ expression: ExprSyntax) -> TokenSyntax? {
            guard let member = expression.as(MemberAccessExprSyntax.self), member.declName.argumentNames == nil,
                  member.base?.as(DeclReferenceExprSyntax.self)?.baseName.sourceIdentifierName == binder else { return nil }
            return member.declName.baseName
        }
        var writes: [FieldAssignment] = []
        for item in closure.statements {
            guard case .expr(let expression) = item.item, let (lhs, adds, rhs) = assignment(expression),
                  let target = field(lhs) else {
                throw Problem(node: Syntax(item), message: "Assign to whole fields of \(binder), for example \(binder).y = \(binder).x.")
            }
            if let source = field(rhs) {
                writes.append(.init(target: target, adds: adds, source: .field(source)))
            } else if let value = SourceIntegerLiteral.value(rhs) {
                writes.append(.init(target: target, adds: adds, source: .integer(value)))
            } else {
                throw Problem(node: Syntax(rhs), message: "Use whole fields of \(binder) or an Int literal on the right side of this assignment.")
            }
        }
        return writes
    }

    private static func assignment(_ expression: ExprSyntax) -> (ExprSyntax, Bool, ExprSyntax)? {
        let lhs: ExprSyntax, op: ExprSyntax, rhs: ExprSyntax
        if let infix = expression.as(InfixOperatorExprSyntax.self) {
            (lhs, op, rhs) = (infix.leftOperand, infix.operator, infix.rightOperand)
        } else if let sequence = expression.as(SequenceExprSyntax.self), sequence.elements.count == 3,
                  let first = sequence.elements.first, let middle = sequence.elements.dropFirst().first,
                  let last = sequence.elements.last {
            (lhs, op, rhs) = (first, middle, last)
        } else {
            return nil
        }
        if op.is(AssignmentExprSyntax.self) { return (lhs, false, rhs) }
        guard op.as(BinaryOperatorExprSyntax.self)?.operator.text == "+=" else { return nil }
        return (lhs, true, rhs)
    }
}
