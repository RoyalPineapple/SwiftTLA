import Foundation

/// Identity of run-owned storage, separate from model variables and parameters.
public struct CheckingRegisterReference: Hashable, Sendable {
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

public struct CheckingRegister<Value: TLAValueType>: Sendable {
    package let reference: CheckingRegisterReference
}

package struct CheckingRegisterDeclaration: Sendable {
    package let reference: CheckingRegisterReference
    package let swiftType: String
    package let initial: StateExpr

    package init(reference: CheckingRegisterReference, swiftType: String, initial: StateExpr) {
        self.reference = reference
        self.swiftType = swiftType
        self.initial = initial
    }
}
