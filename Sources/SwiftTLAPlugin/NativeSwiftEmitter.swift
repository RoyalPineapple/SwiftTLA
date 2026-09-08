import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftTLA

/// Translates the resolved compiler program into typed Swift expressions.
/// This object exists only while expanding the macro.
struct NativeSwiftEmitter {
    let model: MacroCompilation
    let plan: NativeMachinePlan
    var types: NativeTypeInference
    var records: [NativeType] = []
    var atoms: [String] = []
    var finiteValues: [[CompiledValue]] = []
    var operatorSpecializations: [NativeOperatorSpecialization: Int] = [:]
    private struct CallbackParameter: Hashable {
        let operation: OperatorID
        let arguments: [NativeType]
        let result: NativeType
        init(operation: OperatorID, call: NativeOperatorCall) {
            self.operation = operation
            arguments = call.parameters.map { call.inference.bindings[$0] ?? .unknown }
            result = call.result
        }
    }
    private var hasDepthScope = false
    private var callbackFunctions: [CallbackParameter: String] = [:]

    init(model: MacroCompilation) throws {
        self.model = model
        plan = NativeMachinePlan(compilation: model.compilation)
        types = try NativeTypeInference(plan: plan, sourceTypes: model.nativeSourceTypes)
    }

    func unsupported(_ operation: String) -> CompilationDiagnostic {
        CompilationDiagnostic(
            code: .unsupportedGeneratedValueShape, stage: .validation,
            path: "native.\(operation)", expected: "a statically typed native Swift operation",
            actual: operation,
            nextSafeAction: "Express this operation using the supported typed model surface."
        )
    }

    mutating func swiftType(_ type: NativeType) throws -> String {
        switch type {
        case .int: return "Int"
        case .bool: return "Bool"
        case .string: return "String"
        case .atom: return "_Atom"
        case .control: return "_ControlLocation"
        case .named(let name): return name
        case .collectionMember(_, let name): return name
        case .finite(let members):
            if let index = finiteValues.firstIndex(of: members) { return "NativeValue\(index)" }
            finiteValues.append(members)
            return "NativeValue\(finiteValues.count - 1)"
        case .set(let element): return "Set<\(try swiftType(element))>"
        case .array(let element): return "[\(try swiftType(element))]"
        case .dictionary(let key, let value): return "[\(try swiftType(key)): \(try swiftType(value))]"
        case .record, .tuple:
            if let index = records.firstIndex(of: type) { return "NativeRecord\(index)" }
            records.append(type)
            return "NativeRecord\(records.count - 1)"
        case .unknown: throw unsupported("unresolved value type")
        }
    }

    func variable(_ id: VariableID) -> String {
        let declaration = plan.variables.first { $0.id == id }?.declaration.name ?? "variable"
        let name = String(declaration.unicodeScalars.map { scalar -> Character in
            switch scalar.value {
            case 65...90, 97...122, 48...57, 95: Character(String(scalar))
            default: "_"
            }
        })
        return "_value_\(name)_\(id.ordinal)"
    }
    func binder(_ id: BinderID) -> String { "b\(id.ordinal)" }

    func fieldName(_ type: NativeType, index: Int) -> String {
        switch type {
        case .record(let fields): return "`\(fields[index].name)`"
        case .tuple(let elements): return elements.count == 2 ? (index == 0 ? "first" : "second") : "element\(index + 1)"
        default: preconditionFailure("Field naming requires resolved record or tuple evidence")
        }
    }

    func finiteCaseName(_ members: [CompiledValue], index: Int) -> String {
        let display: String
        switch members[index] {
        case .string(let value), .constant(let value): display = value
        case .integer(let value): display = value < 0 ? "minus_" + String(value.magnitude) : String(value)
        case .boolean(let value): display = value ? "true" : "false"
        default: display = "value"
        }
        let name = String(display.unicodeScalars.map { scalar -> Character in
            switch scalar.value {
            case 65...90, 97...122, 48...57, 95: Character(String(scalar))
            default: "_"
            }
        })
        return "member_\(name)_\(index)"
    }

    mutating func literal(_ value: CompiledValue, as type: NativeType) throws -> String {
        if case .collectionMember(let variable, _) = type {
            guard let collection = model.compilation.machineSurfacePlan.variables.first(where: { $0.storageOrdinal == variable.ordinal })?.collection,
                  let index = collection.members.firstIndex(where: { CompiledValue(formal: $0) == value }) else {
                throw unsupported("literal outside collection domain")
            }
            return "\(nativeCollectionBinding(collection, in: model))[\(index)]"
        }
        if case .finite(let members) = type {
            guard let index = members.firstIndex(of: value) else { throw unsupported("literal outside finite union") }
            return "\(try swiftType(type)).\(finiteCaseName(members, index: index))"
        }
        if case .named(let name) = type {
            if let info = model.enumInfos.first(where: { $0.typeName == name }),
               let item = info.cases.first(where: { CompiledValue(formal: $0.value) == value }) {
                return "\(name).\(item.name)"
            }
            throw unsupported("literal of \(name)")
        }
        switch (value, type) {
        case (.integer(let value), .int): return value == Int.min ? "Int.min" : String(value)
        case (.boolean(let value), .bool): return String(value)
        case (.string(let value), .string): return String(reflecting: value)
        case (.constant(let value), .atom):
            if let index = atoms.firstIndex(of: value) { return "_Atom.atom\(index)" }
            atoms.append(value)
            return "_Atom.atom\(atoms.count - 1)"
        case (.controlLocation(let id), .control): return "_ControlLocation.location\(id.ordinal)"
        case (.set(let values), .set(let element)):
            return "Set<\(try swiftType(element))>([\(try values.sorted().map { try literal($0, as: element) }.joined(separator: ", "))])"
        case (.tuple(let values), .array(let element)):
            return "[\(try values.map { try literal($0, as: element) }.joined(separator: ", "))]"
        case (.tuple(let values), .tuple(let elements)) where values.count == elements.count:
            let name = try swiftType(type)
            return "\(name)(\(try zip(values, elements).enumerated().map { index, item in "\(fieldName(type, index: index)): \(try literal(item.0, as: item.1))" }.joined(separator: ", ")))"
        case (.function(let values), .dictionary(let key, let element)):
            if values.isEmpty { return "[\(try swiftType(key)): \(try swiftType(element))]()" }
            return "[\(try values.keys.sorted().map { "\(try literal($0, as: key)): \(try literal(values[$0]!, as: element))" }.joined(separator: ", "))]"
        case (.record(let value), .record(let fields)):
            let name = try swiftType(type)
            let arguments = try fields.enumerated().map { index, field in
                guard let value = value.fields.first(where: { $0.key == .string(field.name) })?.value else {
                    throw unsupported("record field \(field.name)")
                }
                return "\(fieldName(type, index: index)): \(try literal(value, as: field.type))"
            }
            return "\(name)(\(arguments.joined(separator: ", ")))"
        default: throw unsupported("literal \(value) as \(type)")
        }
    }

    mutating func projected(_ value: String, from source: NativeType, to destination: NativeType?) throws -> String {
        guard let destination, source != destination else { return value }
        guard types.canProjectRead(source, to: destination) else {
            throw unsupported("native projection from \(source) to \(destination)")
        }
        let cases: String
        switch source {
        case .named(let name):
            guard let info = model.enumInfos.first(where: { $0.typeName == name }) else { throw unsupported("enum declaration for \(name)") }
            cases = try info.cases.map { item in
                "case .\(item.name): return \(try literal(.init(formal: item.value), as: destination))"
            }.joined(separator: "\n")
        case .finite(let members):
            cases = try members.indices.map { index in
                "case .\(finiteCaseName(members, index: index)): return \(try literal(members[index], as: destination))"
            }.joined(separator: "\n")
        default: throw unsupported("native projection from \(source) to \(destination)")
        }
        return "({ (value: \(try swiftType(source))) -> \(try swiftType(destination)) in switch value { \(cases) } })(\(value))"
    }

    /// Emits a native comparator matching CompiledValue's structural order.
    mutating func ordering(_ type: NativeType) throws -> String {
        let name = try swiftType(type)
        let body: String
        switch type {
        case .int, .string: body = "return lhs < rhs"
        case .bool: body = "return !lhs && rhs"
        case .control, .atom: body = "return lhs.rawValue < rhs.rawValue"
        case .finite(let members):
            let cases = members.indices.map { "case .\(finiteCaseName(members, index: $0)): return \($0)" }.joined(separator: "\n")
            body = "func rank(_ value: \(name)) -> Int { switch value { \(cases) } }; return rank(lhs) < rank(rhs)"
        case .named(let name):
            if let info = model.enumInfos.first(where: { $0.typeName == name }) {
                let ordered = info.cases.sorted { CompiledValue(formal: $0.value) < CompiledValue(formal: $1.value) }
                let cases = ordered.enumerated().map { "case .\($0.element.name): return \($0.offset)" }.joined(separator: "\n")
                body = "func rank(_ value: \(name)) -> Int { switch value { \(cases) } }; return rank(lhs) < rank(rhs)"
            } else { throw unsupported("ordering opaque type \(name)") }
        case .collectionMember(let variable, _):
            guard let collection = model.compilation.machineSurfacePlan.variables.first(where: { $0.storageOrdinal == variable.ordinal })?.collection else {
                throw unsupported("collection ordering domain")
            }
            let indices = collection.members.indices.sorted { CompiledValue(formal: collection.members[$0]) < CompiledValue(formal: collection.members[$1]) }
            let members = indices.map { "\(nativeCollectionBinding(collection, in: model))[\($0)]" }.joined(separator: ", ")
            body = "let ordered = [\(members)]; return (ordered.firstIndex(of: lhs) ?? Int.max) < (ordered.firstIndex(of: rhs) ?? Int.max)"
        case .array(let element):
            body = "return lhs.lexicographicallyPrecedes(rhs, by: \(try ordering(element)))"
        case .set(let element):
            let order = try ordering(element)
            body = "let order = \(order); return lhs.sorted(by: order).lexicographicallyPrecedes(rhs.sorted(by: order), by: order)"
        case .dictionary(let key, let value):
            let keyOrder = try ordering(key)
            let valueOrder = try ordering(value)
            body = """
            let keyOrder = \(keyOrder)
            let valueOrder = \(valueOrder)
            let left = lhs.sorted { keyOrder($0.key, $1.key) }
            let right = rhs.sorted { keyOrder($0.key, $1.key) }
            return left.lexicographicallyPrecedes(right) { a, b in
                a.key == b.key ? valueOrder(a.value, b.value) : keyOrder(a.key, b.key)
            }
            """
        case .record(let fields):
            body = try fields.enumerated().map { index, field in
                "if lhs.\(fieldName(type, index: index)) != rhs.\(fieldName(type, index: index)) { return (\(try ordering(field.type)))(lhs.\(fieldName(type, index: index)), rhs.\(fieldName(type, index: index))) }"
            }.joined(separator: "\n") + "\nreturn false"
        case .tuple(let elements):
            body = try elements.enumerated().map { index, element in
                "if lhs.\(fieldName(type, index: index)) != rhs.\(fieldName(type, index: index)) { return (\(try ordering(element)))(lhs.\(fieldName(type, index: index)), rhs.\(fieldName(type, index: index))) }"
            }.joined(separator: "\n") + "\nreturn false"
        case .unknown: throw unsupported("unresolved structural order")
        }
        return "{ (lhs: \(name), rhs: \(name)) -> Bool in \(body) }"
    }

    mutating func operatorCall(
        _ id: OperatorID, arguments: [CompiledFormalCallArgument], expected: NativeType?,
        state: String, substitutions: [BinderID: String],
        operators: [OperatorID: CompiledLocalOperator], activeOperators: Set<NativeOperatorSpecialization>
    ) throws -> String {
        let ownsDepth = !hasDepthScope
        hasDepthScope = true
        defer { if ownsDepth { hasDepthScope = false } }
        let resolved = try types.operatorCall(id, arguments: arguments, expected: expected, operators: operators)
        let values = arguments.compactMap { argument -> CompiledStateExpr? in
            if case .value(let value) = argument { return value }; return nil
        }
        var argumentsCode: [String] = []
        for (parameter, argument) in zip(resolved.parameters, values) {
            guard let parameterType = resolved.inference.bindings[parameter] else { throw unsupported("operator parameter evidence") }
            let code = try self.expression(argument, expected: parameterType, state: state, substitutions: substitutions, operators: operators, activeOperators: activeOperators)
            argumentsCode.append("{ \(code) }")
        }
        if types.isOperatorParameter(id) {
            let parameter = CallbackParameter(operation: id, call: resolved)
            guard let function = callbackFunctions[parameter] else { throw unsupported("callback signature evidence") }
            return "(try \(function)(\(argumentsCode.joined(separator: ", "))))"
        }
        let code = try emitOperator(resolved, argumentsCode: argumentsCode, state: state,
            substitutions: substitutions, operators: operators, activeOperators: activeOperators)
        return ownsDepth ? "(try { () throws -> \(try swiftType(resolved.result)) in var _nativeDepth = 0; return \(code) }())" : code
    }

    private mutating func emitOperator(
        _ resolved: NativeOperatorCall, argumentsCode valueArguments: [String],
        state: String, substitutions: [BinderID: String],
        operators: [OperatorID: CompiledLocalOperator], activeOperators: Set<NativeOperatorSpecialization>
    ) throws -> String {
        let key = resolved.specialization
        let ordinal: Int
        if let existing = operatorSpecializations[key] { ordinal = existing }
        else { ordinal = operatorSpecializations.count; operatorSpecializations[key] = ordinal }
        let function = "_operator\(ordinal)"
        let resultType = try swiftType(resolved.result)
        var argumentsCode = valueArguments
        var declarations: [String] = []
        var nested = substitutions
        var nestedCallbacks = callbackFunctions
        for parameter in resolved.parameters {
            guard let parameterType = resolved.inference.bindings[parameter] else { throw unsupported("operator parameter evidence") }
            declarations.append("_ \(binder(parameter)): @escaping () throws -> \(try swiftType(parameterType))")
            nested[parameter] = "(try \(binder(parameter))())"
        }
        // Operator parameters are ordinary Swift closures. Each demanded shape
        // has its own typed parameter; no callback value is erased at runtime.
        for id in resolved.callbackUses.keys.sorted(by: { $0.ordinal < $1.ordinal }) {
            guard let actual = resolved.callbackArguments[id] else { continue }
            for (index, use) in (resolved.callbackUses[id] ?? []).enumerated() {
                let name = "_callback\(id.ordinal)_\(index)"
                let parameter = CallbackParameter(operation: id, call: use)
                let argumentTypes = try use.parameters.map { binder -> String in
                    guard let type = use.inference.bindings[binder] else { throw unsupported("callback parameter evidence") }
                    return try swiftType(type)
                }
                let callbackResult = try swiftType(use.result)
                let signature = "(" + argumentTypes.map { "@escaping () throws -> \($0)" }.joined(separator: ", ") + ") throws -> \(callbackResult)"
                declarations.append("_ \(name): @escaping \(signature)")
                nestedCallbacks[parameter] = name
                if case .reference(let origin, _) = actual, types.isOperatorParameter(origin) {
                    guard let forwarded = callbackFunctions[.init(operation: origin, call: use)] else { throw unsupported("forwarded callback signature evidence") }
                    argumentsCode.append(forwarded)
                } else {
                    let names = argumentTypes.indices.map { "_callbackArgument\($0)" }
                    let parameters = zip(names, argumentTypes).map { "\($0.0): @escaping () throws -> \($0.1)" }.joined(separator: ", ")
                    let code = try emitOperator(use, argumentsCode: names, state: state,
                        substitutions: substitutions, operators: operators, activeOperators: activeOperators.union([key]))
                    argumentsCode.append("{ (\(parameters)) throws -> \(callbackResult) in return \(code) }")
                }
            }
        }
        let call = "try \(function)(\(argumentsCode.joined(separator: ", ")))"
        if activeOperators.contains(key) { return "(\(call))" }
        let callerTypes = types
        let callerCallbacks = callbackFunctions
        types = resolved.inference
        callbackFunctions = nestedCallbacks
        defer { types = callerTypes; callbackFunctions = callerCallbacks }
        let bodyCode = try self.expression(resolved.body, expected: resolved.result, state: state, substitutions: nested, operators: operators, activeOperators: activeOperators.union([key]))
        let domainGuard: String
        if let domain = resolved.domain, let parameter = resolved.parameters.first {
            let condition = try self.expression(.in(.boundValue(parameter), domain), expected: .bool, state: state, substitutions: nested, operators: operators, activeOperators: activeOperators.union([key]))
            domainGuard = "guard \(condition) else { throw NativeMachineEvaluationError.functionArgumentOutsideDomain }"
        } else { domainGuard = "" }
        return """
        (try { () throws -> \(resultType) in
            func \(function)(\(declarations.joined(separator: ", "))) throws -> \(resultType) {
                guard _nativeDepth < _NativeMachineOperations.maximumRecursiveDepth else {
                    throw NativeMachineEvaluationError.recursionDepthExceeded(_NativeMachineOperations.maximumRecursiveDepth)
                }
                _nativeDepth += 1
                defer { _nativeDepth -= 1 }
                \(domainGuard)
                return \(bodyCode)
            }
            return \(call)
        }())
        """
    }

    mutating func expression(
        _ expression: CompiledStateExpr,
        expected: NativeType? = nil,
        state: String = "state.",
        substitutions: [BinderID: String] = [:],
        operators: [OperatorID: CompiledLocalOperator] = [:],
        activeOperators: Set<NativeOperatorSpecialization> = []
    ) throws -> String {
        func type(_ expression: CompiledStateExpr, _ expected: NativeType? = nil) throws -> NativeType {
            try types.type(of: expression, expected: expected)
        }
        // Nested emission retains the resolved lexical identities; it does not resolve names again.
        func emit(_ value: CompiledStateExpr, _ expected: NativeType? = nil) throws -> String {
            try self.expression(value, expected: expected, state: state, substitutions: substitutions,
                                operators: operators, activeOperators: activeOperators)
        }
        func binary(_ lhs: CompiledStateExpr, _ op: String, _ rhs: CompiledStateExpr, _ operand: NativeType? = nil) throws -> String {
            let operandType = try operand ?? types.operandType(lhs, rhs)
            return "(\(try emit(lhs, operandType)) \(op) \(try emit(rhs, operandType)))"
        }
        func arithmetic(_ name: String, _ lhs: CompiledStateExpr, _ rhs: CompiledStateExpr) throws -> String {
            "(try _NativeMachineOperations.\(name)(\(try emit(lhs, .int)), \(try emit(rhs, .int))))"
        }
        switch expression {
        case .value(let value): return try literal(value, as: expected ?? type(expression))
        case .stateVariable(let id):
            guard let source = types.variables[id] else { throw unsupported("state variable type") }
            return try projected(state + variable(id), from: source, to: expected)
        case .boundValue(let id):
            guard let source = types.bindings[id] else { throw unsupported("bound value type") }
            return try projected(substitutions[id] ?? binder(id), from: source, to: expected)
        case .controlLocation(let id): return "_ControlLocation.location\(id.ordinal)"
        case .enabledAction(let id): return "enabled.contains(\(id.ordinal))"
        case .add(let a, let b): return try arithmetic("add", a, b)
        case .subtract(let a, let b): return try arithmetic("subtract", a, b)
        case .multiply(let a, let b): return try arithmetic("multiply", a, b)
        case .divide(let a, let b), .integerDivide(let a, let b), .modulo(let a, let b):
            let operation: String
            if case .modulo = expression { operation = "modulo" } else { operation = "divide" }
            return """
            (try { () throws -> Int in
                let _rightOperand = \(try emit(b, .int))
                let _leftOperand = \(try emit(a, .int))
                return try _NativeMachineOperations.\(operation)(_leftOperand, _rightOperand)
            }())
            """
        case .negate(let a): return "(try _NativeMachineOperations.negate(\(try emit(a, .int))))"
        case .equal(let a, let b): return try binary(a, "==", b)
        case .notEqual(let a, let b): return try binary(a, "!=", b)
        case .lessThan(let a, let b): return try binary(a, "<", b, .int)
        case .lessOrEqual(let a, let b): return try binary(a, "<=", b, .int)
        case .greaterThan(let a, let b): return try binary(a, ">", b, .int)
        case .greaterOrEqual(let a, let b): return try binary(a, ">=", b, .int)
        case .and(let a, let b):
            return try Self.shortCircuitBoolean(left: emit(a, .bool), right: emit(b, .bool), conjunction: true)
        case .or(let a, let b):
            return try Self.shortCircuitBoolean(left: emit(a, .bool), right: emit(b, .bool), conjunction: false)
        case .not(let a): return "(!\(try emit(a, .bool)))"
        case .ifThenElse(let condition, let then, let otherwise):
            let result = try expected ?? type(expression)
            return "(\(try emit(condition, .bool)) ? \(try emit(then, result)) : \(try emit(otherwise, result)))"
        case .setLiteral(let values):
            guard case .set(let element) = try expected ?? type(expression) else { throw unsupported("set literal") }
            return "Set<\(try swiftType(element))>([\(try values.map { try emit($0, element) }.joined(separator: ", "))])"
        case .tupleLiteral(let values):
            let result = try expected ?? type(expression)
            switch result {
            case .array(let element): return "[\(try values.map { try emit($0, element) }.joined(separator: ", "))]"
            case .tuple(let elements):
                return "\(try swiftType(result))(\(try zip(values, elements).enumerated().map { index, item in "\(fieldName(result, index: index)): \(try emit(item.0, item.1))" }.joined(separator: ", ")))"
            default: throw unsupported("tuple literal")
            }
        case .in(let value, let domain):
            let element = try types.membershipElementType(value: value, domain: domain)
            return "(\(try emit(domain, .set(element))).contains(\(try emit(value, element))))"
        case .subset(let a, let b):
            let context = try types.operandType(a, b)
            return "(\(try emit(a, context)).isSubset(of: \(try emit(b, context))))"
        case .union(let a, let b):
            let result = try expected ?? type(expression)
            return "(\(try emit(a, result)).union(\(try emit(b, result))))"
        case .intersection(let a, let b):
            let result = try expected ?? type(expression)
            return "(\(try emit(a, result)).intersection(\(try emit(b, result))))"
        case .setDifference(let a, let b):
            let result = try expected ?? type(expression)
            return "(\(try emit(a, result)).subtracting(\(try emit(b, result))))"
        case .cardinality(let a): return "(\(try emit(a)).count)"
        case .integerRange(let a, let b): return "(try _NativeMachineOperations.integerRange(\(try emit(a, .int)), \(try emit(b, .int))))"
        case .setFilter(let domain, let binding, let predicate):
            guard case .set(let element) = try types.type(of: expression, expected: expected) else { throw unsupported("set filter") }
            return "Set<\(try swiftType(element))>(try \(try emit(domain, .set(element))).sorted(by: \(try ordering(element))).filter { \(binder(binding)) in \(try emit(predicate, .bool)) })"
        case .setMap(let value, let binding, let domain):
            guard case .set(let element) = try expected ?? type(expression) else { throw unsupported("set map") }
            guard let input = types.bindings[binding] else { throw unsupported("set map binding") }
            return "Set<\(try swiftType(element))>(try \(try emit(domain, .set(input))).sorted(by: \(try ordering(input))).map { \(binder(binding)) in \(try emit(value, element)) })"
        case .forAll(let domain, let binding, let predicate):
            guard let element = types.bindings[binding] else { throw unsupported("quantifier binding") }
            return "(try \(try emit(domain, .set(element))).sorted(by: \(try ordering(element))).allSatisfy { \(binder(binding)) in \(try emit(predicate, .bool)) })"
        case .exists(let domain, let binding, let predicate):
            guard let element = types.bindings[binding] else { throw unsupported("quantifier binding") }
            return "(try \(try emit(domain, .set(element))).sorted(by: \(try ordering(element))).contains { \(binder(binding)) in \(try emit(predicate, .bool)) })"
        case .choose(let domain, let binding, let predicate):
            let element = try types.type(of: expression, expected: expected)
            let order = try ordering(element)
            return "(try _NativeMachineOperations.choose(\(try emit(domain, .set(element))).sorted(by: \(order))) { \(binder(binding)) in \(try emit(predicate, .bool)) })"
        case .sequenceFromSet(let domain):
            guard case .set(let element) = try type(domain) else { throw unsupported("sequence from set") }
            return "(\(try emit(domain)).sorted(by: \(try ordering(element))))"
        case .powerSet(let domain): return "(try _NativeMachineOperations.powerSet(\(try emit(domain))))"
        case .unionAll(let domain):
            guard case .set(let element) = try expected ?? type(expression) else { throw unsupported("UNION result") }
            return "(\(try emit(domain)).reduce(into: Set<\(try swiftType(element))>()) { $0.formUnion($1) })"
        case .functionSet(let domain, let range):
            return "(try _NativeMachineOperations.functionSet(\(try emit(domain)), \(try emit(range))))"
        case .setSum(let function, let domain):
            guard case .set(let key) = try type(domain) else { throw unsupported("set sum") }
            let functionCode = try emit(function, .dictionary(key, .int))
            let domainCode = try emit(domain, .set(key))
            return "(try { () throws -> Int in let mapping = \(functionCode); let members = \(domainCode); return try _NativeMachineOperations.sum(try members.map { try _NativeMachineOperations.functionValue(mapping, at: $0) }) }())"
        case .foldFunction(let operation, let initial, let sequence):
            guard operation.parameters.count == 2 else { throw unsupported("fold arity") }
            let result = try expected ?? type(expression)
            var nested = substitutions
            nested[operation.parameters[0]] = binder(operation.parameters[0])
            nested[operation.parameters[1]] = binder(operation.parameters[1])
            let body = try self.expression(operation.body, expected: result, state: state, substitutions: nested, operators: operators, activeOperators: activeOperators)
            let source = try types.sequenceSourceType(sequence)
            let elements = try nativeSequenceElements(emit(sequence, source), source: source)
            return "(try \(elements).reversed().reduce(\(try emit(initial, result))) { \(binder(operation.parameters[1])), \(binder(operation.parameters[0])) in \(body) })"
        case .tupleAccess(let value, let index):
            let source = try types.projectionSourceType(value, index: index, expected: expected)
            if case .tuple(let fields) = source {
                let field = "\(try emit(value, source)).\(fieldName(source, index: index - 1))"
                return try projected(field, from: fields[index - 1], to: expected)
            }
            let elements = try nativeSequenceElements(emit(value, source), source: source)
            return "(try _NativeMachineOperations.sequenceElement(\(elements), at: \(index)))"
        case .tupleDynamicAccess(let value, let index):
            let source = try types.sequenceSourceType(value, element: expected ?? .unknown)
            let element = try nativeSequenceElementType(source)
            let elements = try nativeSequenceElements("_sequenceValue", source: source)
            return """
            (try { () throws -> \(try swiftType(element)) in
                let _sequenceValue = \(try emit(value, source))
                let _sequenceIndex = \(try emit(index, .int))
                return try _NativeMachineOperations.sequenceElement(\(elements), at: _sequenceIndex)
            }())
            """
        case .tupleLength(let value):
            if case .tuple(let elements) = try type(value) {
                return "(try { () throws -> Int in _ = \(try emit(value)); return \(elements.count) }())"
            }
            let source = try types.sequenceSourceType(value)
            return "(\(try nativeSequenceElements(emit(value, source), source: source)).count)"
        case .tupleHead(let value):
            let source = try types.sequenceSourceType(value, element: expected ?? .unknown)
            return "(try _NativeMachineOperations.sequenceHead(\(try nativeSequenceElements(emit(value, source), source: source))))"
        case .tupleTail(let value):
            let result = try expected ?? type(expression)
            guard case .array(let element) = result else { throw unsupported("sequence tail result") }
            let source = try types.sequenceSourceType(value, element: element)
            return "(try _NativeMachineOperations.sequenceTail(\(try nativeSequenceElements(emit(value, source), source: source))))"
        case .tupleAppend(let a, let b):
            let result = try expected ?? type(expression)
            guard case .array(let element) = result else { throw unsupported("sequence append result") }
            let source = try types.sequenceSourceType(a, element: element)
            let elements = try nativeSequenceElements("_sequenceValue", source: source)
            return """
            (try { () throws -> \(try swiftType(result)) in
                let _sequenceValue = \(try emit(a, source))
                let _appendedValue = \(try emit(b, element))
                return \(elements) + [_appendedValue]
            }())
            """
        case .tupleConcatenate(let a, let b):
            let result = try expected ?? type(expression)
            guard case .array(let element) = result else { throw unsupported("sequence concatenation result") }
            let left = try types.sequenceSourceType(a, element: element)
            let right = try types.sequenceSourceType(b, element: element)
            return """
            (try { () throws -> \(try swiftType(result)) in
                let _leftValue = \(try emit(a, left))
                let _rightValue = \(try emit(b, right))
                let _rightElements = \(try nativeSequenceElements("_rightValue", source: right))
                let _leftElements = \(try nativeSequenceElements("_leftValue", source: left))
                return _leftElements + _rightElements
            }())
            """
        case .domain(let value):
            switch try type(value) {
            case .dictionary: return "Set(\(try emit(value)).keys)"
            case .array: return "_NativeMachineOperations.sequenceDomain(\(try emit(value)))"
            case .tuple(let values):
                let domain = values.isEmpty ? "Set<Int>()" : "Set(1...\(values.count))"
                return "(try { () throws -> Set<Int> in _ = \(try emit(value)); return \(domain) }())"
            case .record(let fields):
                let domain = "Set<String>([\(fields.map { String(reflecting: $0.name) }.joined(separator: ", "))])"
                return "(try { () throws -> Set<String> in _ = \(try emit(value)); return \(domain) }())"
            default: throw unsupported("DOMAIN")
            }
        case .functionLiteral(let domain, let binding, let value):
            guard case .dictionary(let input, let result) = try expected ?? type(expression) else { throw unsupported("function literal") }
            return "Dictionary(uniqueKeysWithValues: try \(try emit(domain, .set(input))).sorted(by: \(try ordering(input))).map { (\(binder(binding)): \(try swiftType(input))) throws -> (\(try swiftType(input)), \(try swiftType(result))) in (\(binder(binding)), \(try emit(value, result))) })"
        case .functionApply(let function, let argument):
            if case .operatorReference(let id) = function {
                return try operatorCall(id, arguments: [.value(argument)], expected: expected, state: state, substitutions: substitutions, operators: operators, activeOperators: activeOperators)
            }
            let result = try type(expression, expected)
            let base = try type(function)
            let hint: NativeType
            switch base {
            case .array: hint = .array(result)
            case .dictionary(let key, _): hint = .dictionary(key, result)
            case .tuple(let elements):
                if case .value(.integer(let index)) = argument, index >= 1, index <= elements.count {
                    var updated = elements; updated[index - 1] = result; hint = .tuple(updated)
                } else { hint = base }
            case .record(let fields):
                if case .value(.string(let name)) = argument {
                    hint = .record(fields.map { .init(name: $0.name, type: $0.name == name ? result : $0.type) })
                } else { hint = base }
            default: hint = base
            }
            let source = try type(function, hint)
            let key: NativeType
            let access: String
            switch source {
            case .dictionary(let domain, _):
                key = domain
                access = "return try _NativeMachineOperations.functionValue(_functionValue, at: _functionArgument)"
            case .array:
                key = .int
                access = "return try _NativeMachineOperations.sequenceFunctionValue(_functionValue, at: _functionArgument)"
            case .tuple(let elements):
                key = .int
                if case .value(.integer(let index)) = argument {
                    if index >= 1, index <= elements.count {
                        access = "return _functionValue.\(fieldName(source, index: index - 1))"
                    } else { access = "throw NativeMachineEvaluationError.tupleIndexOutsideDomain(_functionArgument)" }
                } else {
                    let cases = elements.indices.map { "case \($0 + 1): return _functionValue.\(fieldName(source, index: $0))" }.joined(separator: "\n")
                    access = "switch _functionArgument { \(cases)\ndefault: throw NativeMachineEvaluationError.tupleIndexOutsideDomain(_functionArgument) }"
                }
            case .record(let fields):
                key = .string
                if case .value(.string(let name)) = argument {
                    if fields.contains(where: { $0.name == name }) { access = "return _functionValue.\(name)" }
                    else { access = "throw NativeMachineEvaluationError.recordFieldUnavailable(_functionArgument)" }
                } else {
                    let cases = fields.map { "case \(String(reflecting: $0.name)): return _functionValue.\($0.name)" }.joined(separator: "\n")
                    access = "switch _functionArgument { \(cases)\ndefault: throw NativeMachineEvaluationError.recordFieldUnavailable(_functionArgument) }"
                }
            default: throw unsupported("function application")
            }
            return """
            (try { () throws -> \(try swiftType(result)) in
                let _functionArgument = \(try emit(argument, key))
                let _functionValue = \(try emit(function, source))
                \(access)
            }())
            """
        case .except(let original, let key, let value):
            let originalType = try type(original)
            let keyType: NativeType
            let replacementType: NativeType
            let update: String
            switch originalType {
            case .dictionary(let domain, let element):
                keyType = domain; replacementType = element
                update = "return _NativeMachineOperations.functionUpdated(_originalValue, at: _updatedKey, to: _replacementValue)"
            case .array(let element):
                keyType = .int; replacementType = element
                update = "return _NativeMachineOperations.sequenceUpdated(_originalValue, at: _updatedKey, to: _replacementValue)"
            case .record(let fields):
                keyType = .string
                let selected: Int?
                if case .value(.string(let name)) = key {
                    selected = fields.firstIndex { $0.name == name }
                    replacementType = try selected.map { fields[$0].type } ?? type(value)
                } else {
                    selected = nil
                    replacementType = try fields.first?.type ?? type(value)
                    guard fields.allSatisfy({ $0.type == replacementType }) else {
                        throw unsupported("dynamic record keys require homogeneous field types")
                    }
                }
                let nativeName = try swiftType(originalType)
                func replacing(_ selected: Int) -> String {
                    let arguments = fields.indices.map { index in
                        let name = fieldName(originalType, index: index)
                        return "\(name): " + (index == selected ? "_replacementValue" : "_originalValue.\(name)")
                    }.joined(separator: ", ")
                    return "return \(nativeName)(\(arguments))"
                }
                if case .value(.string) = key {
                    update = selected.map(replacing) ?? "return _originalValue"
                } else {
                    let branches = fields.indices.map { index in
                        "case \(String(reflecting: fields[index].name)): \(replacing(index))"
                    }.joined(separator: "\n")
                    update = "switch _updatedKey {\n\(branches)\ndefault: return _originalValue\n}"
                }
            default: throw unsupported("EXCEPT")
            }
            // Match the formal evaluator: replacement, original, then key.
            return """
            (try { () throws -> \(try swiftType(originalType)) in
                let _replacementValue = \(try emit(value, replacementType))
                let _originalValue = \(try emit(original, originalType))
                let _updatedKey = \(try emit(key, keyType))
                \(update)
            }())
            """
        case .recordLiteral(let record):
            let result = try expected ?? type(expression)
            guard case .record(let fields) = result else { throw unsupported("record literal") }
            let evaluated = try record.fields.enumerated().map { index, field in
                guard case .string(let name) = field.key,
                      let type = fields.first(where: { $0.name == name })?.type else { throw unsupported("record field") }
                return "let _recordField\(index): \(try swiftType(type)) = \(try emit(field.value, type))"
            }
            let arguments = try fields.enumerated().map { index, field in
                guard let sourceIndex = record.fields.firstIndex(where: { $0.key == .string(field.name) }) else { throw unsupported("record field") }
                return "\(fieldName(result, index: index)): _recordField\(sourceIndex)"
            }
            return """
            (try { () throws -> \(try swiftType(result)) in
                \(evaluated.joined(separator: "\n"))
                return \(try swiftType(result))(\(arguments.joined(separator: ", ")))
            }())
            """
        case .recordAccess(let value, _, let key):
            let source = try types.recordProjectionSourceType(value, key: key, expected: expected)
            guard case .record(let fields) = source, case .string(let name) = key,
                  let index = fields.firstIndex(where: { $0.name == name }) else { throw unsupported("record access") }
            let field = "\(try emit(value, source)).\(fieldName(source, index: index))"
            return try projected(field, from: fields[index].type, to: expected)
        case .caseExpr(let first, let remaining, let otherwise):
            let result = try expected ?? type(expression)
            var body = ""
            for branch in [first] + remaining {
                body += "if \(try emit(branch.condition, .bool)) { return \(try emit(branch.value, result)) }\n"
            }
            body += try otherwise.map { "return \(try emit($0, result))" } ?? "throw NativeMachineEvaluationError.noMatchingCase"
            return "(try { () throws -> \(try swiftType(result)) in\n\(body)\n}())"
        case .letValue(let binding, let value, let body):
            let result = try expected ?? type(expression)
            var nested = substitutions
            nested[binding] = "(try \(binder(binding))())"
            let valueType = try types.bindings[binding] ?? type(value)
            let valueCode = try emit(value, valueType)
            let bodyCode = try self.expression(body, expected: result, state: state, substitutions: nested, operators: operators, activeOperators: activeOperators)
            return "(try { () throws -> \(try swiftType(result)) in func \(binder(binding))() throws -> \(try swiftType(valueType)) { return \(valueCode) }; return \(bodyCode) }())"
        case .letIn(let definitions, let body):
            var nested = operators
            definitions.forEach { nested[$0.id] = $0 }
            return try self.expression(body, expected: expected, state: state, substitutions: substitutions, operators: nested, activeOperators: activeOperators)
        case .operatorApplication(let id, let arguments):
            return try operatorCall(id, arguments: arguments, expected: expected, state: state, substitutions: substitutions, operators: operators, activeOperators: activeOperators)
        case .recursiveCall(let id, let arguments):
            return try operatorCall(id, arguments: arguments.map { .value($0) }, expected: expected, state: state, substitutions: substitutions, operators: operators, activeOperators: activeOperators)
        case .lambdaApplication(let lambda, let arguments):
            let ownsDepth = !hasDepthScope
            hasDepthScope = true
            defer { if ownsDepth { hasDepthScope = false } }
            let resolved = try types.lambdaCall(lambda, arguments: arguments, expected: expected)
            var values: [String] = []
            for (binding, argument) in zip(resolved.parameters, arguments) {
                guard let argumentType = resolved.inference.bindings[binding] else { throw unsupported("lambda parameter evidence") }
                values.append("{ \(try emit(argument, argumentType)) }")
            }
            let code = try emitOperator(resolved, argumentsCode: values, state: state,
                substitutions: substitutions, operators: operators, activeOperators: activeOperators)
            return ownsDepth ? "(try { () throws -> \(try swiftType(resolved.result)) in var _nativeDepth = 0; return \(code) }())" : code
        default: throw unsupported(String(describing: expression))
        }
    }
}

private func nativeSequenceElementType(_ source: NativeType) throws -> NativeType {
    switch source {
    case .array(let element), .dictionary(.int, let element): return element
    default:
        throw CompilationDiagnostic(code: .unsupportedGeneratedValueShape, stage: .lowering,
            path: "native.sequence", expected: "an array or integer-keyed function",
            actual: source.swiftType, nextSafeAction: "Use a sequence-compatible value.")
    }
}

private func nativeSequenceElements(_ code: String, source: NativeType) throws -> String {
    _ = try nativeSequenceElementType(source)
    if case .array = source { return code }
    return "(try _NativeMachineOperations.sequenceElements(\(code)))"
}
