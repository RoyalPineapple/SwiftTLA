import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftTLA

/// Translates the resolved compiler program into typed Swift expressions.
/// This object exists only while expanding the macro.
struct NativeSwiftEmitter {
    let model: MacroCompilation
    let plan: NativeMachinePlan
    let program: NativeResolvedProgram
    var records: [NativeType] = []
    var atoms: [String] = []
    var finiteValues: [[CompiledValue]] = []
    var unions: [[NativeType]] = []
    private var hasDepthScope = false
    private var callbackFunctions: [NativeCallbackID: String] = [:]

    init(model: MacroCompilation) {
        self.model = model
        plan = NativeMachinePlan(compilation: model.compilation)
        program = model.nativeProgram
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
        case .union(let alternatives):
            if let index = unions.firstIndex(of: alternatives) { return "NativeUnion\(index)" }
            unions.append(alternatives)
            return "NativeUnion\(unions.count - 1)"
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
        if case .union(let alternatives) = type {
            for (index, alternative) in alternatives.enumerated() {
                if let payload = try? literal(value, as: alternative) {
                    return "\(try swiftType(type)).alternative\(index + 1)(\(payload))"
                }
            }
            throw unsupported("literal outside union")
        }
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
                return "\(name).`\(item.name)`"
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
            return "\(name)(\(try values.indices.map { index in "\(fieldName(type, index: index)): \(try literal(values[index], as: elements[index]))" }.joined(separator: ", ")))"
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
        if case .union = source { return try unionProjection(value, from: source, to: destination, checked: false) }
        if case .union(let alternatives) = destination {
            guard let index = alternatives.firstIndex(where: { program.canProject(source: source, to: $0) }) else {
                throw unsupported("union injection")
            }
            return "\(try swiftType(destination)).alternative\(index + 1)(\(try projected(value, from: source, to: alternatives[index])))"
        }
        if case .dictionary(let sourceKey, let sourceValue) = source,
           case .dictionary(let targetKey, let targetValue) = destination {
            let key = try projected("entry.key", from: sourceKey, to: targetKey)
            let item = try projected("entry.value", from: sourceValue, to: targetValue)
            return "Dictionary<\(try swiftType(targetKey)), \(try swiftType(targetValue))>(uniqueKeysWithValues: (\(value)).map { entry in (\(key), \(item)) })"
        }
        if case .set(let input) = source, case .set(let output) = destination {
            return "Set<\(try swiftType(output))>((\(value)).map { element in \(try projected("element", from: input, to: output)) })"
        }
        if case .array(let input) = source, case .array(let output) = destination {
            return "(\(value)).map { element in \(try projected("element", from: input, to: output)) }"
        }
        let sourceFields: [NativeType]?
        let destinationFields: [NativeType]?
        switch (source, destination) {
        case (.tuple(let input), .tuple(let output)):
            sourceFields = input; destinationFields = output
        case (.record(let input), .record(let output)):
            sourceFields = input.map(\.type); destinationFields = output.map(\.type)
        default: sourceFields = nil; destinationFields = nil
        }
        if let sourceFields, let destinationFields {
            let arguments = try zip(sourceFields, destinationFields).enumerated().map { index, pair in
                "\(fieldName(destination, index: index)): \(try projected("source." + fieldName(source, index: index), from: pair.0, to: pair.1))"
            }.joined(separator: ", ")
            return "({ (source: \(try swiftType(source))) -> \(try swiftType(destination)) in \(try swiftType(destination))(\(arguments)) })(\(value))"
        }
        let cases: String
        switch source {
        case .named(let name):
            guard let info = model.enumInfos.first(where: { $0.typeName == name }) else { throw unsupported("enum declaration for \(name)") }
            cases = try info.cases.map { item in
                "case .`\(item.name)`: return \(try literal(.init(formal: item.value), as: destination))"
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
                let cases = ordered.enumerated().map { "case .`\($0.element.name)`: return \($0.offset)" }.joined(separator: "\n")
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
        case .union(let alternatives): body = try unionOrdering(alternatives)
        case .unknown: throw unsupported("unresolved structural order")
        }
        return "{ (lhs: \(name), rhs: \(name)) -> Bool in \(body) }"
    }

    private mutating func resolvedCall(
        _ call: NativeResolvedCall, argumentRoots: [NativeExpressionID], state: String, substitutions: [BinderID: String],
        activeFunctions: Set<NativeFunctionID>
    ) throws -> String {
        let ownsDepth = !hasDepthScope
        hasDepthScope = true
        defer { if ownsDepth { hasDepthScope = false } }
        let arguments = try argumentRoots.map {
            "{ \(try expression($0, state: state, substitutions: substitutions, activeFunctions: activeFunctions)) }"
        }
        switch call.target {
        case .callback(let id):
            guard let function = callbackFunctions[id] else { throw unsupported("resolved callback capture") }
            return "(try \(function)(\(arguments.joined(separator: ", "))))"
        case .function(let id):
            let code = try emitFunction(id, arguments: arguments, callbacks: call.callbacks,
                state: state, substitutions: substitutions, activeFunctions: activeFunctions)
            return ownsDepth ? "(try { () throws -> \(try swiftType(program[id].resultType)) in var _nativeDepth = 0; return \(code) }())" : code
        }
    }

    private mutating func emitFunction(
        _ id: NativeFunctionID, arguments valueArguments: [String], callbacks: [NativeResolvedCallbackArgument],
        state: String, substitutions: [BinderID: String], activeFunctions: Set<NativeFunctionID>
    ) throws -> String {
        let resolved = program[id]
        let function = "_operator\(id.ordinal)"
        var arguments = valueArguments
        var declarations: [String] = []
        var nested = substitutions
        var nestedCallbacks = callbackFunctions
        for (parameter, type) in zip(resolved.parameters, resolved.parameterTypes) {
            declarations.append("_ \(binder(parameter)): @escaping () throws -> \(try swiftType(type))")
            nested[parameter] = "(try \(binder(parameter))())"
        }
        for callback in resolved.callbacks {
            let signature = program[callback]
            let name = "_callback\(callback.ordinal)"
            let argumentTypes = try signature.parameters.map { try swiftType($0) }
            let result = try swiftType(signature.result)
            declarations.append("_ \(name): @escaping (\(argumentTypes.map { "@escaping () throws -> \($0)" }.joined(separator: ", "))) throws -> \(result)")
            nestedCallbacks[callback] = name
            guard let target = callbacks.first(where: { $0.parameter == callback })?.target else {
                guard let captured = callbackFunctions[callback] else { throw unsupported("resolved callback argument") }
                arguments.append(captured)
                continue
            }
            switch target {
            case .callback(let origin):
                guard let captured = callbackFunctions[origin] else { throw unsupported("forwarded callback") }
                arguments.append(captured)
            case .function(let target):
                let names = argumentTypes.indices.map { "_callbackArgument\($0)" }
                let parameters = zip(names, argumentTypes).map { "\($0.0): @escaping () throws -> \($0.1)" }.joined(separator: ", ")
                let code = try emitFunction(target, arguments: names, callbacks: [], state: state,
                    substitutions: substitutions, activeFunctions: activeFunctions.union([id]))
                arguments.append("{ (\(parameters)) throws -> \(result) in return \(code) }")
            }
        }
        let call = "try \(function)(\(arguments.joined(separator: ", ")))"
        if activeFunctions.contains(id) { return "(\(call))" }
        let outerCallbacks = callbackFunctions
        callbackFunctions = nestedCallbacks
        defer { callbackFunctions = outerCallbacks }
        let body = try expression(resolved.body, state: state, substitutions: nested, activeFunctions: activeFunctions.union([id]))
        let domainGuard = try resolved.domainGuard.map {
            "guard \(try expression($0, state: state, substitutions: nested, activeFunctions: activeFunctions.union([id]))) else { throw NativeMachineEvaluationError.functionArgumentOutsideDomain }"
        } ?? ""
        return """
        (try { () throws -> \(try swiftType(resolved.resultType)) in
            func \(function)(\(declarations.joined(separator: ", "))) throws -> \(try swiftType(resolved.resultType)) {
                guard _nativeDepth < _NativeMachineOperations.maximumRecursiveDepth else {
                    throw NativeMachineEvaluationError.recursionDepthExceeded(_NativeMachineOperations.maximumRecursiveDepth)
                }
                _nativeDepth += 1
                defer { _nativeDepth -= 1 }
                \(domainGuard)
                return \(body)
            }
            return \(call)
        }())
        """
    }

    mutating func expression(
        _ id: NativeExpressionID, state: String = "state.", substitutions: [BinderID: String] = [:],
        activeFunctions: Set<NativeFunctionID> = []
    ) throws -> String {
        let node = program[id]
        let value = try expressionBody(id, state: state, substitutions: substitutions, activeFunctions: activeFunctions)
        return try projected(value, from: node.computationType, to: node.resultType)
    }

    private mutating func expressionBody(
        _ id: NativeExpressionID, state: String, substitutions: [BinderID: String],
        activeFunctions: Set<NativeFunctionID>
    ) throws -> String {
        let node = program[id]
        let expression = node.expression
        func childType(_ index: Int) -> NativeType { program[node.children[index]].resultType }
        func emit(_ index: Int) throws -> String {
            try self.expression(node.children[index], state: state, substitutions: substitutions, activeFunctions: activeFunctions)
        }
        func binary(_ operation: String) throws -> String {
            "(\(try emit(0)) \(operation) \(try emit(1)))"
        }
        func arithmetic(_ name: String) throws -> String {
            "(try _NativeMachineOperations.\(name)(\(try emit(0)), \(try emit(1))))"
        }
        switch expression {
        case .value(let value): return try literal(value, as: node.computationType)
        case .stateVariable(let id):
            return state + variable(id)
        case .boundValue(let id):
            return substitutions[id] ?? binder(id)
        case .controlLocation(let id): return "_ControlLocation.location\(id.ordinal)"
        case .enabledAction(let id): return "enabled.contains(\(id.ordinal))"
        case .assertView:
            return try checkedView(emit(0), from: childType(0), to: node.computationType)
        case .add(_, _): return try arithmetic("add")
        case .subtract(_, _): return try arithmetic("subtract")
        case .multiply(_, _): return try arithmetic("multiply")
        case .divide(_, _), .integerDivide(_, _), .modulo(_, _):
            let operation: String
            if case .modulo = expression { operation = "modulo" } else { operation = "divide" }
            return """
            (try { () throws -> Int in
                let _rightOperand = \(try emit(1))
                let _leftOperand = \(try emit(0))
                return try _NativeMachineOperations.\(operation)(_leftOperand, _rightOperand)
            }())
            """
        case .negate(_): return "(try _NativeMachineOperations.negate(\(try emit(0))))"
        case .equal(_, _): return try binary("==")
        case .notEqual(_, _): return try binary("!=")
        case .lessThan(_, _): return try binary("<")
        case .lessOrEqual(_, _): return try binary("<=")
        case .greaterThan(_, _): return try binary(">")
        case .greaterOrEqual(_, _): return try binary(">=")
        case .and(_, _):
            return try Self.shortCircuitBoolean(left: emit(0), right: emit(1), conjunction: true)
        case .or(_, _):
            return try Self.shortCircuitBoolean(left: emit(0), right: emit(1), conjunction: false)
        case .not(_): return "(!\(try emit(0)))"
        case .ifThenElse(_, _, _):
            return "(\(try emit(0)) ? \(try emit(1)) : \(try emit(2)))"
        case .setLiteral(let values):
            guard case .set(let element) = node.computationType else { throw unsupported("set literal") }
            return "Set<\(try swiftType(element))>([\(try values.indices.map { try emit($0) }.joined(separator: ", "))])"
        case .tupleLiteral(let values):
            let result = node.computationType
            switch result {
            case .array: return "[\(try values.indices.map { try emit($0) }.joined(separator: ", "))]"
            case .tuple:
                return "\(try swiftType(result))(\(try values.indices.map { index in "\(fieldName(result, index: index)): \(try emit(index))" }.joined(separator: ", ")))"
            default: throw unsupported("tuple literal")
            }
        case .in(_, _):
            return "(\(try emit(1)).contains(\(try emit(0))))"
        case .subset(_, _):
            return "(\(try emit(0)).isSubset(of: \(try emit(1))))"
        case .union(_, _):
            return "(\(try emit(0)).union(\(try emit(1))))"
        case .intersection(_, _):
            return "(\(try emit(0)).intersection(\(try emit(1))))"
        case .setDifference(_, _):
            return "(\(try emit(0)).subtracting(\(try emit(1))))"
        case .cardinality(_): return "(\(try emit(0)).count)"
        case .integerRange(_, _): return "(try _NativeMachineOperations.integerRange(\(try emit(0)), \(try emit(1))))"
        case .setFilter(_, let binding, _):
            guard case .set(let element) = node.computationType else { throw unsupported("set filter") }
            return "Set<\(try swiftType(element))>(try \(try emit(0)).sorted(by: \(try ordering(element))).filter { \(binder(binding)) in \(try emit(1)) })"
        case .setMap(_, let binding, _):
            guard case .set(let element) = node.computationType else { throw unsupported("set map") }
            guard let input = node.bindings[binding] else { throw unsupported("set map binding") }
            return "Set<\(try swiftType(element))>(try \(try emit(1)).sorted(by: \(try ordering(input))).map { \(binder(binding)) in \(try emit(0)) })"
        case .forAll(_, let binding, _):
            guard let element = node.bindings[binding] else { throw unsupported("quantifier binding") }
            return "(try \(try emit(0)).sorted(by: \(try ordering(element))).allSatisfy { \(binder(binding)) in \(try emit(1)) })"
        case .exists(_, let binding, _):
            guard let element = node.bindings[binding] else { throw unsupported("quantifier binding") }
            return "(try \(try emit(0)).sorted(by: \(try ordering(element))).contains { \(binder(binding)) in \(try emit(1)) })"
        case .choose(_, let binding, _):
            let element = node.computationType
            let order = try ordering(element)
            return "(try _NativeMachineOperations.choose(\(try emit(0)).sorted(by: \(order))) { \(binder(binding)) in \(try emit(1)) })"
        case .sequenceFromSet(_):
            guard case .set(let element) = childType(0) else { throw unsupported("sequence from set") }
            return "(\(try emit(0)).sorted(by: \(try ordering(element))))"
        case .powerSet(_): return "(try _NativeMachineOperations.powerSet(\(try emit(0))))"
        case .unionAll(_):
            guard case .set(let element) = node.computationType else { throw unsupported("UNION result") }
            return "(\(try emit(0)).reduce(into: Set<\(try swiftType(element))>()) { $0.formUnion($1) })"
        case .functionSet(_, _):
            return "(try _NativeMachineOperations.functionSet(\(try emit(0)), \(try emit(1))))"
        case .setSum(_, _):
            let functionCode = try emit(0)
            let domainCode = try emit(1)
            return "(try { () throws -> Int in let mapping = \(functionCode); let members = \(domainCode); return try _NativeMachineOperations.sum(try members.map { try _NativeMachineOperations.functionValue(mapping, at: $0) }) }())"
        case .foldFunction(let operation, _, _):
            guard operation.parameters.count == 2 else { throw unsupported("fold arity") }
            var nested = substitutions
            nested[operation.parameters[0]] = binder(operation.parameters[0])
            nested[operation.parameters[1]] = binder(operation.parameters[1])
            let body = try self.expression(node.children[0], state: state, substitutions: nested, activeFunctions: activeFunctions)
            let source = childType(2)
            let elements = try nativeSequenceElements(emit(2), source: source)
            return "(try \(elements).reversed().reduce(\(try emit(1))) { \(binder(operation.parameters[1])), \(binder(operation.parameters[0])) in \(body) })"
        case .sequenceSelect(_, let binding, _):
            let source = childType(0)
            let elements = try nativeSequenceElements(emit(0), source: source)
            return "(try \(elements).filter { \(binder(binding)) in \(try emit(1)) })"
        case .tupleAccess(_, let index):
            let source = childType(0)
            if case .tuple = source {
                let field = "\(try emit(0)).\(fieldName(source, index: index - 1))"
                return field
            }
            let elements = try nativeSequenceElements(emit(0), source: source)
            return "(try _NativeMachineOperations.sequenceElement(\(elements), at: \(index)))"
        case .tupleDynamicAccess(_, _):
            let source = childType(0)
            let element = try nativeSequenceElementType(source)
            let elements = try nativeSequenceElements("_sequenceValue", source: source)
            return """
            (try { () throws -> \(try swiftType(element)) in
                let _sequenceValue = \(try emit(0))
                let _sequenceIndex = \(try emit(1))
                return try _NativeMachineOperations.sequenceElement(\(elements), at: _sequenceIndex)
            }())
            """
        case .tupleRemoving(_, _):
            let source = childType(0)
            let elements = try nativeSequenceElements("_sequenceValue", source: source)
            return """
            (try { () throws -> \(try swiftType(node.computationType)) in
                let _sequenceValue = \(try emit(0))
                let _sequenceIndex = \(try emit(1))
                return try _NativeMachineOperations.sequenceRemoving(\(elements), at: _sequenceIndex)
            }())
            """
        case .tupleLength(_):
            if case .tuple(let elements) = childType(0) {
                return "(try { () throws -> Int in _ = \(try emit(0)); return \(elements.count) }())"
            }
            let source = childType(0)
            return "(\(try nativeSequenceElements(emit(0), source: source)).count)"
        case .tupleHead(_):
            let source = childType(0)
            return "(try _NativeMachineOperations.sequenceHead(\(try nativeSequenceElements(emit(0), source: source))))"
        case .tupleTail(_):
            let result = node.computationType
            guard case .array = result else { throw unsupported("sequence tail result") }
            let source = childType(0)
            return "(try _NativeMachineOperations.sequenceTail(\(try nativeSequenceElements(emit(0), source: source))))"
        case .tupleAppend(_, _):
            let result = node.computationType
            guard case .array = result else { throw unsupported("sequence append result") }
            let source = childType(0)
            let elements = try nativeSequenceElements("_sequenceValue", source: source)
            return """
            (try { () throws -> \(try swiftType(result)) in
                let _sequenceValue = \(try emit(0))
                let _appendedValue = \(try emit(1))
                return \(elements) + [_appendedValue]
            }())
            """
        case .tupleConcatenate(_, _):
            let result = node.computationType
            guard case .array = result else { throw unsupported("sequence concatenation result") }
            let left = childType(0)
            let right = childType(1)
            return """
            (try { () throws -> \(try swiftType(result)) in
                let _leftValue = \(try emit(0))
                let _rightValue = \(try emit(1))
                let _rightElements = \(try nativeSequenceElements("_rightValue", source: right))
                let _leftElements = \(try nativeSequenceElements("_leftValue", source: left))
                return _leftElements + _rightElements
            }())
            """
        case .domain(_):
            switch childType(0) {
            case .dictionary: return "Set(\(try emit(0)).keys)"
            case .array: return "_NativeMachineOperations.sequenceDomain(\(try emit(0)))"
            case .tuple(let values):
                let domain = values.isEmpty ? "Set<Int>()" : "Set(1...\(values.count))"
                return "(try { () throws -> Set<Int> in _ = \(try emit(0)); return \(domain) }())"
            case .record(let fields):
                let domain = "Set<String>([\(fields.map { String(reflecting: $0.name) }.joined(separator: ", "))])"
                return "(try { () throws -> Set<String> in _ = \(try emit(0)); return \(domain) }())"
            default: throw unsupported("DOMAIN")
            }
        case .functionLiteral(_, let binding, _):
            guard case .dictionary(let input, let result) = node.computationType else { throw unsupported("function literal") }
            return "Dictionary(uniqueKeysWithValues: try \(try emit(0)).sorted(by: \(try ordering(input))).map { (\(binder(binding)): \(try swiftType(input))) throws -> (\(try swiftType(input)), \(try swiftType(result))) in (\(binder(binding)), \(try emit(1))) })"
        case .functionApply(_, let argument):
            if let call = node.call { return try resolvedCall(call, argumentRoots: node.children, state: state, substitutions: substitutions, activeFunctions: activeFunctions) }
            let result = node.computationType
            let source = childType(0)
            let access: String
            switch source {
            case .dictionary:
                access = "return try _NativeMachineOperations.functionValue(_functionValue, at: _functionArgument)"
            case .array:
                access = "return try _NativeMachineOperations.sequenceFunctionValue(_functionValue, at: _functionArgument)"
            case .tuple(let elements):
                if case .value(.integer(let index)) = argument {
                    if index >= 1, index <= elements.count {
                        access = "return _functionValue.\(fieldName(source, index: index - 1))"
                    } else { access = "throw NativeMachineEvaluationError.tupleIndexOutsideDomain(_functionArgument)" }
                } else {
                    let cases = elements.indices.map { "case \($0 + 1): return _functionValue.\(fieldName(source, index: $0))" }.joined(separator: "\n")
                    access = "switch _functionArgument { \(cases)\ndefault: throw NativeMachineEvaluationError.tupleIndexOutsideDomain(_functionArgument) }"
                }
            case .record(let fields):
                if case .value(.string(let name)) = argument {
                    if let index = fields.firstIndex(where: { $0.name == name }) { access = "return _functionValue.\(fieldName(source, index: index))" }
                    else { access = "throw NativeMachineEvaluationError.recordFieldUnavailable(_functionArgument)" }
                } else {
                    let cases = fields.indices.map { "case \(String(reflecting: fields[$0].name)): return _functionValue.\(fieldName(source, index: $0))" }.joined(separator: "\n")
                    access = "switch _functionArgument { \(cases)\ndefault: throw NativeMachineEvaluationError.recordFieldUnavailable(_functionArgument) }"
                }
            default: throw unsupported("function application")
            }
            return """
            (try { () throws -> \(try swiftType(result)) in
                let _functionArgument = \(try emit(1))
                let _functionValue = \(try emit(0))
                \(access)
            }())
            """
        case .except(_, let key, _):
            let originalType = childType(0)
            let update: String
            switch originalType {
            case .dictionary:
                update = "return _NativeMachineOperations.functionUpdated(_originalValue, at: _updatedKey, to: _replacementValue)"
            case .array:
                update = "return _NativeMachineOperations.sequenceUpdated(_originalValue, at: _updatedKey, to: _replacementValue)"
            case .record(let fields):
                let selected: Int?
                if case .value(.string(let name)) = key {
                    selected = fields.firstIndex { $0.name == name }
                } else {
                    selected = nil
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
                let _replacementValue = \(try emit(2))
                let _originalValue = \(try emit(0))
                let _updatedKey = \(try emit(1))
                \(update)
            }())
            """
        case .recordLiteral(let record):
            let result = node.computationType
            guard case .record(let fields) = result else { throw unsupported("record literal") }
            let evaluated = try record.fields.enumerated().map { index, field in
                guard case .string(let name) = field.key,
                      let type = fields.first(where: { $0.name == name })?.type else { throw unsupported("record field") }
                return "let _recordField\(index): \(try swiftType(type)) = \(try emit(index))"
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
        case .recordAccess(_, _, let key):
            let source = childType(0)
            guard case .record(let fields) = source, case .string(let name) = key,
                  let index = fields.firstIndex(where: { $0.name == name }) else { throw unsupported("record access") }
            let field = "\(try emit(0)).\(fieldName(source, index: index))"
            return field
        case .caseExpr(_, let remaining, let otherwise):
            let result = node.computationType
            var body = ""
            for index in 0..<(remaining.count + 1) {
                body += "if \(try emit(index * 2)) { return \(try emit(index * 2 + 1)) }\n"
            }
            body += try otherwise.map { _ in "return \(try emit(node.children.count - 1))" } ?? "throw NativeMachineEvaluationError.noMatchingCase"
            return "(try { () throws -> \(try swiftType(result)) in\n\(body)\n}())"
        case .letValue(let binding, _, _):
            let result = node.computationType
            var nested = substitutions
            nested[binding] = "(try \(binder(binding))())"
            let valueType = childType(0)
            let valueCode = try emit(0)
            let bodyCode = try self.expression(node.children[1], state: state, substitutions: nested, activeFunctions: activeFunctions)
            return "(try { () throws -> \(try swiftType(result)) in func \(binder(binding))() throws -> \(try swiftType(valueType)) { return \(valueCode) }; return \(bodyCode) }())"
        case .letIn: return try emit(0)
        case .operatorApplication:
            guard let call = node.call else { throw unsupported("resolved call") }
            return try resolvedCall(call, argumentRoots: node.children, state: state, substitutions: substitutions, activeFunctions: activeFunctions)
        case .recursiveCall:
            guard let call = node.call else { throw unsupported("resolved call") }
            return try resolvedCall(call, argumentRoots: node.children, state: state, substitutions: substitutions, activeFunctions: activeFunctions)
        case .lambdaApplication:
            guard let call = node.call else { throw unsupported("resolved lambda call") }
            return try resolvedCall(call, argumentRoots: node.children, state: state, substitutions: substitutions, activeFunctions: activeFunctions)
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
