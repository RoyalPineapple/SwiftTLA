import SwiftTLA

extension MacroExpander {
    static func generateMachineSchema(model: MacroCompilation) -> String {
        let plan = model.machineSurface
        let formalVariables = Dictionary(uniqueKeysWithValues: model.compilation.spec.variables.map { ($0.name, $0.initial) })
        let fields = plan.variables.map { variable in
            let value = formalVariables[variable.formalName] ?? .constant("unknown")
            return """
            .init(id: \"\(variable.formalName)\", display: .init(name: \"\(variable.formalName)\"), value: \(schemaValue(value)), swiftType: \"\(variable.swiftType)\")
            """
        }.joined(separator: ",\n                ")
        let actions = plan.actions.map { action in
            let parameters = action.bindings.map { binding in
                return ".init(id: \"\(binding.formalName)\", display: .init(name: \"\(binding.formalName)\"), value: \(schemaValue(binding.domain[0])), swiftType: \"\(binding.swiftType)\")"
            }.joined(separator: ", ")
            return ".init(id: \"\(action.formalName)\", display: .init(name: \"\(action.formalName)\"), parameters: [\(parameters)])"
        }.joined(separator: ",\n                ")
        return """
        public static let machineSchema = MachineSchema(
            identifier: \"\(plan.schemaIdentifier)\",
            model: .init(name: \"\(model.typeName)\"),
            state: [
                \(fields)
            ],
            actions: [
                \(actions)
            ]
        )
        """
    }

    private static func schemaValue(_ value: TLAValue) -> String {
        switch value {
        case .int: return ".integer"
        case .bool: return ".boolean"
        case .string: return ".string"
        case .constant: return ".constant"
        case .set(let values):
            guard let first = values.sorted().first else { return ".set(element: .opaque)" }
            return ".set(element: \(schemaValue(first)))"
        case .tuple(let values):
            return ".tuple(elements: [\(values.map(schemaValue).joined(separator: ", "))])"
        case .record(let fields):
            let entries = fields.fields.map {
                ".init(id: \"\($0.name)\", display: .init(name: \"\($0.name)\"), value: \(schemaValue($0.value)))"
            }.joined(separator: ", ")
            return ".record(fields: [\(entries)])"
        case .function(let values):
            guard let first = values.sorted(by: { $0.key.description < $1.key.description }).first else {
                return ".function(key: .opaque, value: .opaque)"
            }
            return ".function(key: \(schemaValue(first.key)), value: \(schemaValue(first.value)))"
        }
    }
}
