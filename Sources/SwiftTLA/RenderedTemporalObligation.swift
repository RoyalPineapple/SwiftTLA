/// A serialized proof obligation, emitted only at the formal-tool boundary.
@_documentation(visibility: internal)
public struct _RenderedTemporalObligation: Sendable, Equatable {
    package let initialCondition: String
    package let property: String

    public init(initialCondition: String, property: String) {
        self.initialCondition = initialCondition
        self.property = property
    }
}

extension CompiledTLARenderer {
    func temporalObligations(_ expression: TemporalCondition<CompiledStateQuery>) throws -> [_RenderedTemporalObligation]? {
        func containsConditional(_ condition: TemporalCondition<CompiledStateQuery>) -> Bool {
            switch condition {
            case .conditional: true
            case .all(let children): children.contains(where: containsConditional)
            default: false
            }
        }
        guard containsConditional(expression) else { return nil }
        func visit(_ condition: TemporalCondition<CompiledStateQuery>, path: [(String, Bool)]) throws -> [_RenderedTemporalObligation] {
            switch condition {
            case .conditional(let predicate, let yes, let no):
                let guardText = try state(predicate.expression)
                return try visit(yes, path: path + [(guardText, true)])
                    + visit(no, path: path + [(guardText, false)])
            case .all(let children) where !children.isEmpty:
                return try children.flatMap { try visit($0, path: path) }
            default:
                var initial = "TRUE"
                for (predicate, selected) in path.reversed() {
                    initial = selected
                        ? "(IF \(predicate) THEN \(initial) ELSE FALSE)"
                        : "(IF \(predicate) THEN FALSE ELSE \(initial))"
                }
                return [.init(initialCondition: initial, property: try temporal(condition))]
            }
        }
        return try visit(expression, path: [])
    }
}
