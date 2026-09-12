import SwiftTLA

/// Generated nominal types, including nested fields, resolved before Swift emission.
struct NativeTypeDeclarations: Sendable {
    let names: [CompiledValueType: String]
    let records: [CompiledValueType]
    let unions: [[CompiledValueType]]
    let finiteValues: [[CompiledValue]]
    let modelValueCases: [String: String]

    init(program: CompiledProgram) {
        let variableTypes = program.variableTypes.sorted { $0.key.ordinal < $1.key.ordinal }.map(\.value)
        let bindingTypes = program.bindingTypes.sorted { $0.key.ordinal < $1.key.ordinal }.map(\.value)
        var pending = program.behavior.initializations.map { initialization in
            switch initialization.initialization {
            case .value(let expression), .memberOf(let expression): expression
            }
        }
        pending.append(contentsOf: program.behavior.temporalProperties.flatMap { $0.expression.predicates.map(\.expression) })
        pending.append(contentsOf: program.behavior.invariants.map { $0.predicate.expression })
        pending.append(contentsOf: [program.behavior.constraint, program.behavior.assume].compactMap { $0?.expression })
        var actions = program.behavior.actions.map(\.body)
        while let action = actions.popLast() {
            switch action {
            case .assign(_, let value), .guard_(let value): pending.append(value)
            case .unchanged: break
            case .existsAction(_, let domain, let body), .define(_, let domain, let body):
                pending.append(domain)
                actions.append(body)
            case .ifElse(let condition, let yes, let no):
                pending.append(condition)
                actions.append(contentsOf: [yes, no])
            case .and(let lhs, let rhs), .or(let lhs, let rhs): actions.append(contentsOf: [lhs, rhs])
            }
        }
        var expressions: Set<CompiledExpression> = []
        var executionExpressions: [CompiledExpression] = []
        var functions: Set<ResolvedFunctionID> = []
        while let expression = pending.popLast() {
            guard expressions.insert(expression).inserted else { continue }
            executionExpressions.append(expression)
            pending.append(contentsOf: expression.children)
            if case .call(let id) = expression.operation, functions.insert(id).inserted {
                let function = program[id]
                pending.append(function.body)
                if let guardExpression = function.domainGuard { pending.append(guardExpression) }
            }
        }
        let executionFunctions = program.functions.enumerated().filter {
            functions.contains(.init(ordinal: $0.offset))
        }.map(\.element)
        let expressionTypes = executionExpressions.map(\.resultType)
        let functionTypes = executionFunctions.flatMap { $0.parameters.map(\.type) + [$0.resultType] }
        let literals = executionExpressions.compactMap { node -> CompiledValue? in
            guard case .value(let value) = node.operation else { return nil }
            return value
        }
        let parameterValues = program.behavior.actions.flatMap { $0.bindings.flatMap(\.values) }
        self.init(
            types: variableTypes + bindingTypes + expressionTypes + functionTypes,
            literals: literals + parameterValues,
            namedDomains: program.enums.domains
        )
    }

    init(types: [CompiledValueType], literals: [CompiledValue], namedDomains: [String: Set<CompiledValue>]) {
        var names: [CompiledValueType: String] = [:]
        var records: [CompiledValueType] = []
        var unions: [[CompiledValueType]] = []
        var finiteValues: [[CompiledValue]] = []
        var visited: Set<CompiledValueType> = []
        var pending = Array(types.reversed())
        while let type = pending.popLast() {
            guard visited.insert(type).inserted else { continue }
            switch type {
            case .record, .tuple:
                names[type] = "NativeRecord\(records.count)"
                records.append(type)
            case .union(let alternatives):
                names[type] = "NativeUnion\(unions.count)"
                unions.append(alternatives)
            case .finite(let members):
                names[type] = "NativeValue\(finiteValues.count)"
                finiteValues.append(members)
            default: break
            }
            pending.append(contentsOf: type.components.reversed())
        }
        var modelValues: Set<String> = []
        if visited.contains(.modelValue) {
            var values = literals + finiteValues.flatMap { $0 }
            for case .named(let name) in visited {
                values.append(contentsOf: namedDomains[name] ?? [])
            }
            var visitedValues: Set<CompiledValue> = []
            while let value = values.popLast() {
                guard visitedValues.insert(value).inserted else { continue }
                switch value {
                case .constant(let name): modelValues.insert(name)
                case .set(let members): values.append(contentsOf: members)
                case .tuple(let members): values.append(contentsOf: members)
                case .record(let record): values.append(contentsOf: record.fields.map(\.value))
                case .function(let entries):
                    values.append(contentsOf: entries.keys)
                    values.append(contentsOf: entries.values)
                case .integer, .boolean, .string, .controlLocation: break
                }
            }
        }
        let values = modelValues.sorted()
        let caseNames = GeneratedMachineAPI.generatedIdentifiers(values, fallback: "modelValue")
        modelValueCases = Dictionary(uniqueKeysWithValues: zip(values, caseNames))
        self.names = names
        self.records = records
        self.unions = unions
        self.finiteValues = finiteValues
    }
}
