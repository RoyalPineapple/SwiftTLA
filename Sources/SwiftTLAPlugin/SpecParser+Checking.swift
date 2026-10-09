import SwiftSyntax
import SwiftTLA

extension ParserSession {
    func decodeCheckingExpression(_ expression: ExprSyntax, scope: TypedFacadeScope) -> StateExpr? {
        if let member = expression.as(MemberAccessExprSyntax.self),
           ["checkingLevel", "checkingDiameter"].contains(member.declName.baseName.sourceIdentifierName),
           let owner = member.base?.as(DeclReferenceExprSyntax.self), scope.isCheckingScope(owner) {
            return member.declName.baseName.sourceIdentifierName == "checkingLevel"
                ? .checkingLevel : .checkingDiameter
        }
        guard let call = expression.as(FunctionCallExprSyntax.self),
              call.trailingClosure == nil, call.additionalTrailingClosures.isEmpty,
              let member = call.calledExpression.as(MemberAccessExprSyntax.self),
              member.declName.baseName.sourceIdentifierName == "set", let base = member.base,
              case .checkingRegister(let reference)? = decodeTypedFacadeValue(base, scope: scope),
              call.arguments.count == 1, let argument = call.arguments.first, argument.label == nil,
              let value = decodeTypedFacadeValue(argument.expression, scope: scope) else { return nil }
        return .setCheckingRegister(reference, value)
    }
}
