import Foundation

/// Identity of a parameter declaration, independent of its report name.
public struct ParameterReference: Hashable, Sendable {
    private let identity: UUID
    package let name: String
    package let sourceSpan: CompilerSourceSpan

    package init(name: String, sourceOffset: Int? = nil, sourceLength: Int = 0) {
        identity = UUID()
        self.name = name
        sourceSpan = .init(location: sourceOffset.map(CompilerSourceSpan.Location.utf8Offset) ?? .unavailable,
            utf8Length: sourceLength)
    }
}

/// A typed, immutable input to a model, not an assignable state variable.
public struct ModelParameter<Value: TLAValueType>: TypedExpression, Sendable {
    package let reference: ParameterReference

    package init(reference: ParameterReference) {
        self.reference = reference
    }

    public var expr: Expr<Value> { Expr(.parameter(reference)) }
    public var stateExpr: StateExpr { expr.stateExpr }
}

package struct ModelParameterDeclaration: Sendable {
    package let reference: ParameterReference
    package let swiftType: String
    package let domain: StateExpr

    package init(reference: ParameterReference, swiftType: String, domain: StateExpr) {
        self.reference = reference
        self.swiftType = swiftType
        self.domain = domain
    }
}
