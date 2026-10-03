import SwiftTLA

/// Generated nominal types, including nested fields, resolved before Swift emission.
struct NativeTypeDeclarations: Sendable {
    let names: [CompiledValueType: String]
    let records: [CompiledValueType]
    let nominalRecords: [CompiledValueType]
    let enumNames: Set<String>
    let unions: [[CompiledValueType]]
    let finiteValues: [[CompiledValue]]
    let modelValueCases: [String: String]

    init(program: CompiledProgram) {
        var types: [CompiledValueType] = []
        var values: [CompiledValue] = []
        var pendingPrograms = [program]
        var visited: Set<CompilationIdentity> = []
        while let program = pendingPrograms.popLast() {
            guard visited.insert(program.identity).inserted else { continue }
            let variableTypes = program.variableTypes.sorted { $0.key.ordinal < $1.key.ordinal }.map(\.value)
            let bindingTypes = program.bindingTypes.sorted { $0.key.ordinal < $1.key.ordinal }.map(\.value)
            var pending = program.behavior.initializations.map { initialization in
                switch initialization.initialization {
                case .value(let expression), .memberOf(let expression): expression
                }
            }
            pending.append(contentsOf: program.layout.parameters.compactMap { program.behavior.parameterDomains[$0.binder] })
            pending.append(contentsOf: program.layout.checkingRegisters.compactMap {
                program.behavior.checkingRegisterInitializations[$0.id]
            })
            pending.append(contentsOf: program.behavior.validationScenarios.flatMap { $0.bindings.values })
            pending.append(contentsOf: program.behavior.actions.flatMap { $0.bindings.map(\.domain) })
            pending.append(contentsOf: program.behavior.temporalProperties.flatMap { $0.expression.predicates.map(\.expression) })
            pending.append(contentsOf: program.behavior.temporalProperties.flatMap { $0.bindings.map(\.domain) })
            pending.append(contentsOf: program.behavior.fairness.compactMap(\.projection))
            pending.append(contentsOf: program.refinements.flatMap { $0.variableMappings.map(\.expression) })
            pending.append(contentsOf: program.behavior.invariants.map { $0.predicate.expression })
            pending.append(contentsOf: program.behavior.reachabilityProperties.map { $0.predicate.expression })
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
            var functions: Set<ResolvedFunctionID> = []
            types += variableTypes + bindingTypes
            types += program.checkingRegisterTypes.sorted { $0.key.ordinal < $1.key.ordinal }.map(\.value)
            while let expression = pending.popLast() {
                guard expressions.insert(expression).inserted else { continue }
                types.append(expression.resultType)
                if case .value(let value) = expression.operation { values.append(value) }
                pending.append(contentsOf: expression.children)
                if case .call(let id) = expression.operation, functions.insert(id).inserted {
                    let function = program[id]
                    pending.append(function.body)
                    if let guardExpression = function.domainGuard { pending.append(guardExpression) }
                }
            }
            for id in functions.sorted(by: { $0.ordinal < $1.ordinal }) {
                let function = program[id]
                types += function.parameters.map(\.type) + [function.resultType]
            }
            pendingPrograms.append(contentsOf: program.refinements.map(\.abstract))
        }
        self.init(types: types, literals: values, namedDomains: program.enums.domains)
    }

    init(types: [CompiledValueType], literals: [CompiledValue], namedDomains: [String: Set<CompiledValue>]) {
        var names: [CompiledValueType: String] = [:]
        var records: [CompiledValueType] = []
        var nominalRecords: [CompiledValueType] = []
        var unions: [[CompiledValueType]] = []
        var finiteValues: [[CompiledValue]] = []
        var visited: Set<CompiledValueType> = []
        var pending = Array(types.reversed())
        while let type = pending.popLast() {
            guard visited.insert(type).inserted else { continue }
            switch type {
            case .nominalRecord:
                nominalRecords.append(type)
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
            modelValues = CompiledValue.modelValueNames(in: values)
        }
        let values = modelValues.sorted()
        let caseNames = GeneratedMachineAPI.generatedIdentifiers(values, fallback: "modelValue")
        modelValueCases = Dictionary(uniqueKeysWithValues: zip(values, caseNames))
        self.names = names
        self.records = records
        self.nominalRecords = nominalRecords
        self.enumNames = Set(visited.compactMap {
            if case .named(let name) = $0 { return name }
            return nil
        })
        self.unions = unions
        self.finiteValues = finiteValues
    }
}
