import Foundation

public struct PropertyReference: Hashable, Sendable {
    private let identity = UUID()
    package let name: String

    package init(name: String) { self.name = name }
}

public protocol ModelProperty: SpecComponent {
    var reference: PropertyReference { get }
}

public enum ValidationExpectation: String, Sendable, Codable {
    case satisfied
    case violated
}

public struct ValidationBinding: Sendable {
    package let parameter: ParameterReference
    package let value: StateExpr
    package init(parameter: ParameterReference, value: StateExpr) {
        self.parameter = parameter
        self.value = value
    }
}

public func Bind<Value: TLAValueType>(_ parameter: ModelParameter<Value>, to value: Value) -> ValidationBinding {
    .init(parameter: parameter.reference, value: .value(value.tlaValue))
}

@resultBuilder
public enum ValidationBuilder {
    public static func buildBlock(_ bindings: ValidationBinding...) -> [ValidationBinding] { bindings }
}

public struct ValidationDeclaration: SpecComponent {
    package let name: String
    package let bindings: [ValidationBinding]
    package var expectations: [(property: PropertyReference, expected: ValidationExpectation)] = []
    package var deadlockExpectations: [ValidationExpectation] = []

    package init(name: String, bindings: [ValidationBinding]) {
        self.name = name
        self.bindings = bindings
    }

    public func expect(_ property: some ModelProperty, _ expected: ValidationExpectation) -> Self {
        var copy = self
        copy.expectations.append((property.reference, expected))
        return copy
    }

    public func expectDeadlock(_ expected: ValidationExpectation) -> Self {
        var copy = self
        copy.deadlockExpectations.append(expected)
        return copy
    }
}

public func Validation(_ name: String, @ValidationBuilder _ bindings: () -> [ValidationBinding]) -> ValidationDeclaration {
    .init(name: name, bindings: bindings())
}
