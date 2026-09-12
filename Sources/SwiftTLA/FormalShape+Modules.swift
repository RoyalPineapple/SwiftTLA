extension FormalValueShape {
    var requiredStandardModules: Set<StandardModule> {
        switch self {
        case .integer: [.integers]
        case .set(let item), .sequence(let item): item.requiredStandardModules
        case .tuple(let items): items.reduce(into: []) { $0.formUnion($1.requiredStandardModules) }
        case .function(let key, let value), .union(let key, let value):
            key.requiredStandardModules.union(value.requiredStandardModules)
        case .record(let fields): fields.reduce(into: []) { $0.formUnion($1.shape.requiredStandardModules) }
        case .boolean, .string, .finite, .unsupported: []
        }
    }
}
