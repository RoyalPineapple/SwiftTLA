import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftParser
import SwiftTLA

extension NativeSwiftEmitter {
    var hasRandomSubsetInitializer: Bool {
        program.behavior.initializations.contains { initialization in
            guard case .memberOf(let expression) = initialization.initialization else { return false }
            if case .randomSubset = expression.computation.operation { return true }
            return false
        }
    }

    private mutating func machineStateDeclarations(
        configurationParameters: String, configurationArguments: String
    ) throws -> [DeclSyntax] {
        let api = model.api
        let appendedParameters = configurationParameters.isEmpty ? "" : ", \(configurationParameters)"
        let appendedArguments = configurationArguments.isEmpty ? "" : ", \(configurationArguments)"
        var declarations: [DeclSyntax] = []
        declarations += try configurationDeclarations()
        declarations += try propertyIdentityDeclarations()
        declarations += try validationDeclarations()
        let hiddenVariables = program.layout.variables.filter { stateMemberNames[$0.id] == nil }
        let hiddenFields = try hiddenVariables.map { variable in
            (name: self.variable(variable.id), type: try swiftType(program.variableTypes[variable.id]!))
        }
        let fields = hiddenFields.map { "let \($0.name): \($0.type)" }.joined(separator: "\n")
        let registers = program.layout.checkingRegisters
        let registerNames = GeneratedMachineAPI.generatedIdentifiers(registers.map { $0.reference.name }, fallback: "register")
        let registerFields = try zip(registers, registerNames).map { register, name in
            "public var \(name): \(try swiftType(program.checkingRegisterTypes[register.id]!))"
        }.joined(separator: "\n")
        let registerInitializers = try zip(registers, registerNames).map { register, name in
            "\(name): \(try expression(program.behavior.checkingRegisterInitializations[register.id]!))"
        }.joined(separator: ", ")
        var machineDeclarations = try nativeDeclarations("""
        public struct CheckingRegisters: Sendable {
            \(registerFields)
        }
        public func initialCheckingRegisters() throws -> CheckingRegisters {
            return CheckingRegisters(\(registerInitializers))
        }
        public func successors(checking context: inout CheckingContext<CheckingRegisters>) throws -> [(action: Action, machine: Self)] {
            var run: CheckingContext<CheckingRegisters>? = context
            defer { context = run! }
            return try _successors(checking: &run)
        }
        public func visitSuccessors(checking context: inout CheckingContext<CheckingRegisters>,
                                    _ visit: (Action, Self) throws -> \(nativeBoolType)) throws -> \(nativeBoolType) {
            var run: CheckingContext<CheckingRegisters>? = context
            defer { context = run! }
            return try _visitSuccessors(checking: &run, visit)
        }
        public func visitValidationOutcomes(checking context: inout CheckingContext<CheckingRegisters>,
                                            _ visit: (Action, Self) throws -> \(nativeBoolType),
                                            onEvaluationFailure: (Action, NativeMachineEvaluationError) throws -> \(nativeBoolType)) throws -> \(nativeBoolType) {
            var run: CheckingContext<CheckingRegisters>? = context
            defer { context = run! }
            return try _visitSuccessors(checking: &run, visit, onEvaluationFailure: onEvaluationFailure)
        }
        public struct Snapshot: Hashable, Sendable {
            public let state: State
            \(fields)
        }
        private var _execution: Snapshot
        """)
        guard let snapshotIndex = machineDeclarations.firstIndex(where: {
            $0.as(StructDeclSyntax.self)?.name.text == "Snapshot"
        }) else { throw unsupported("missing snapshot declaration") }
        var snapshotDeclarations = [machineDeclarations[snapshotIndex]]
        try addStructuralIdentity(to: &snapshotDeclarations, fields: hiddenVariables.map {
            (name: variable($0.id), type: program.variableTypes[$0.id]!)
        }, includingPublicState: true)
        machineDeclarations[snapshotIndex] = snapshotDeclarations[0]
        try verifyGeneratedSnapshotOutput(machineDeclarations[snapshotIndex], hiddenFields: hiddenFields,
            structuralIdentity: hiddenVariables.contains { containsSourceNominal(program.variableTypes[$0.id]!) })
        try verifyGeneratedValidationDelegationOutput(machineDeclarations.first {
            $0.as(FunctionDeclSyntax.self)?.name.text == "visitValidationOutcomes"
        })
        declarations += machineDeclarations
        declarations += try nativeDeclarations("""
        private init(execution: Snapshot\(appendedParameters)) {
            _execution = execution
            \(program.layout.parameters.isEmpty ? "" : "self.configuration = configuration")
        }
        """)
        if hiddenVariables.isEmpty {
            declarations += try nativeDeclarations("""
            @_documentation(visibility: internal)
            public static func _machineForRefinement(_ state: State\(appendedParameters)) -> Self {
                Self(execution: Snapshot(state: state)\(appendedArguments))
            }
            """)
        }
        declarations += try nativeDeclarations("""
        public func hasSameConfiguration(as other: Self) -> \(nativeBoolType) {
            \(program.layout.parameters.isEmpty ? "true" : "configuration == other.configuration")
        }
        """)
        let stateFields = try api.variables.map { variable in
            "public let \(variable.swiftIdentifier): \(try swiftType(program.variableTypes[variable.id]!))"
        }.joined(separator: "\n")
        let stateParameters = try api.variables.map { variable in
            "\(variable.swiftIdentifier) _value\(variable.id.ordinal): \(try swiftType(program.variableTypes[variable.id]!))"
        }.joined(separator: ", ")
        let stateAssignments = api.variables.map { "self.\($0.swiftIdentifier) = _value\($0.id.ordinal)" }.joined(separator: "\n")
        let stateDisplayNames = api.variables.map { variable in
            let declaration = program.layout.variables[variable.id.ordinal]
            return "\\State.\(variable.swiftIdentifier): \(String(reflecting: declaration.displayLabel ?? declaration.declaration.name))"
        }.joined(separator: ",\n")
        let stateFormalNames = api.variables.map { variable in
            let declaration = program.layout.variables[variable.id.ordinal]
            return "\\State.\(variable.swiftIdentifier): .init(swiftName: \(String(reflecting: variable.swiftIdentifier)), formalName: \(String(reflecting: declaration.formalName)))"
        }.joined(separator: ",\n")
        var stateDeclarations = try nativeDeclarations("""
        public struct State: Hashable, GeneratedModelFields {
            \(stateFields)
            public static var displayNames: [PartialKeyPath<State>: \(nativeStringType)] {
                [\(stateDisplayNames.isEmpty ? ":" : stateDisplayNames)]
            }
            public static var fieldIdentities: [PartialKeyPath<State>: GeneratedModelFieldIdentity] {
                [\(stateFormalNames.isEmpty ? ":" : stateFormalNames)]
            }
            public init(\(stateParameters)) {
                \(stateAssignments)
            }
        }
        public var state: State { _execution.state }
        public var snapshot: Snapshot { _execution }
        public struct Transition: Equatable, Sendable {
            public let action: Action
            public let before: State
            public let after: State
        }
        """)
        try addStructuralIdentity(to: &stateDeclarations, fields: api.variables.map {
            (name: $0.swiftIdentifier, type: program.variableTypes[$0.id]!)
        })
        try verifyGeneratedStateConstructorOutput(stateDeclarations.first, fields: try api.variables.map {
            (name: $0.swiftIdentifier, type: try swiftType(program.variableTypes[$0.id]!),
             ordinal: $0.id.ordinal, formalName: program.layout.variables[$0.id.ordinal].formalName)
        })
        declarations += stateDeclarations
        return declarations
    }

    mutating func machineMembers(nested: Bool = false) throws -> [DeclSyntax] {
        let api = model.api
        let configurationParameters = machineParameters
        let configurationArguments = machineArguments
        let appendedParameters = configurationParameters.isEmpty ? "" : ", \(configurationParameters)"
        let appendedArguments = configurationArguments.isEmpty ? "" : ", \(configurationArguments)"
        var declarations = try machineStateDeclarations(configurationParameters: configurationParameters,
            configurationArguments: configurationArguments)
        declarations += try formalProjectionDeclarations()
        declarations += try actionDeclarations()
        declarations += try updateDeclarations()
        declarations += try initialDeclarations(parameters: configurationParameters, arguments: configurationArguments)
        let emittedActionIDs = Set(api.actions.map(\.compiledAction)).union(enabledActionIDs)
        if !emittedActionIDs.isEmpty {
            declarations += try nativeDeclarations("""
            private struct _StopSuccessorTraversal: Error {
                let cause: (any Error)?
                init(cause: (any Error)? = nil) { self.cause = cause }
            }
            """)
        }
        declarations += try program.behavior.actions.filter { emittedActionIDs.contains($0.id) }.map {
            try updateFunction($0, configurationParameters: appendedParameters)
        }
        declarations += try enabledDeclarations(configurationParameters: appendedParameters, configurationArguments: appendedArguments)
        let actionFunctions = try api.actions.map { apiAction in
            let action = program[apiAction.compiledAction]
            return try successorFunction(action, api: apiAction, configurationParameters: appendedParameters, configurationArguments: appendedArguments)
        }
        declarations += actionFunctions
        declarations += try dispatchDeclarations(configurationArguments: appendedArguments)
        declarations += try propertyDeclarations(configurationParameters: appendedParameters)
        declarations += try refinementDeclarations(nested: nested)
        if nested {
            declarations += try choiceCacheDeclarations()
            return declarations
        }
        declarations += try exportDeclarations()
        declarations += actorMembers()
        if !program.layout.controlLocations.isEmpty {
            declarations += try nativeDeclarations("""
            @_documentation(visibility: internal)
            public enum _ControlLocation: \(nativeIntType), Hashable, Sendable {
                \(program.layout.controlLocations.map { "case location\($0.id.ordinal) = \($0.id.ordinal)" }.joined(separator: "\n"))
            }
            """)
        }
        declarations += try valueTypeDeclarations()
        declarations += try choiceCacheDeclarations()
        return declarations
    }

    func addStructuralIdentity(
        to declarations: inout [DeclSyntax], fields: [(name: String, type: CompiledValueType)] = [],
        cases: [(name: String, types: [CompiledValueType])] = [], includingPublicState: Bool = false
    ) throws {
        let identity = try structuralIdentityMembers(fields: fields, cases: cases,
            includingPublicState: includingPublicState)
        guard !identity.isEmpty else { return }
        let first = declarations.first
        guard var block = first?.as(StructDeclSyntax.self)?.memberBlock
                ?? first?.as(EnumDeclSyntax.self)?.memberBlock,
              identity.count == 2,
              identity.allSatisfy({ $0.is(FunctionDeclSyntax.self) && !$0.hasError }) else {
            let missing = identity.flatMap { $0.tokens(viewMode: .all) }
                .filter { $0.presence == .missing }.prefix(8).map { String(describing: $0.tokenKind) }
            let name = first?.as(StructDeclSyntax.self)?.name.text
                ?? first?.as(EnumDeclSyntax.self)?.name.text ?? "value"
            throw CompilationDiagnostic(code: .unsupportedGeneratedValueShape, stage: .validation,
                path: "native.\(name).identity", expected: "two complete generated equality and hashing methods",
                actual: "members=\(identity.count), missing tokens=\(missing)",
                nextSafeAction: "Report this native code generation failure.")
        }
        for member in identity {
            block.members.append(MemberBlockItemSyntax(decl: member.with(\.leadingTrivia, .newlines(1))))
        }
        if var value = first?.as(StructDeclSyntax.self) {
            value.memberBlock = block
            declarations[0] = DeclSyntax(value)
        } else if var value = first?.as(EnumDeclSyntax.self) {
            value.memberBlock = block
            declarations[0] = DeclSyntax(value)
        }
    }

    private func structuralIdentityMembers(
        fields: [(name: String, type: CompiledValueType)],
        cases: [(name: String, types: [CompiledValueType])], includingPublicState: Bool
    ) throws -> [DeclSyntax] {
        guard fields.contains(where: { containsSourceNominal($0.type) })
                || cases.contains(where: { $0.types.contains(where: containsSourceNominal) }) else { return [] }
        let bodies = try structuralIdentityBodies(fields: fields, cases: cases,
            includingPublicState: includingPublicState)
        return try nativeDeclarations("""
        public static func == (lhs: Self, rhs: Self) -> \(nativeBoolType) {
            \(bodies.equality)
        }
        public func hash(into hasher: inout SwiftTLA._NativeMachineOperations.StateHasher) {
            \(bodies.hashing)
        }
        """)
    }

    private func structuralEquivalence(_ type: CompiledValueType) throws -> String {
        let bodies = try structuralIdentityBodies(fields: [], cases: [], includingPublicState: false, value: type)
        return "{ (lhs: \(try swiftType(type)), rhs: \(try swiftType(type))) -> \(nativeBoolType) in\n\(bodies.equality)\n}"
    }

    private func structuralIdentityBodies(
        fields: [(name: String, type: CompiledValueType)],
        cases: [(name: String, types: [CompiledValueType])], includingPublicState: Bool,
        value: CompiledValueType? = nil
    ) throws -> (equality: String, hashing: String) {
        let hasherType = "SwiftTLA._NativeMachineOperations.StateHasher"
        var types: [CompiledValueType] = []
        var indices: [CompiledValueType: Int] = [:]
        func index(_ type: CompiledValueType) -> Int {
            if let known = indices[type] { return known }
            let result = types.count
            indices[type] = result
            types.append(type)
            return result
        }
        func equal(_ type: CompiledValueType, _ lhs: String, _ rhs: String) -> String {
            containsSourceNominal(type) ? "_identityEqual\(index(type))(\(lhs), \(rhs))" : "(\(lhs) == \(rhs))"
        }
        func hash(_ type: CompiledValueType, _ value: String, into hasher: String) -> String {
            containsSourceNominal(type)
                ? "_identityHash\(index(type))(\(value), into: &\(hasher))" : "\(hasher).combine(\(value))"
        }
        let equality: String
        let hashing: String
        if let value {
            equality = "return " + equal(value, "lhs", "rhs")
            hashing = hash(value, "value", into: "hasher")
        } else if cases.isEmpty {
            equality = "return " + (includingPublicState ? "(lhs.state == rhs.state) && " : "") + fields.map {
                equal($0.type, "lhs.`" + $0.name + "`", "rhs.`" + $0.name + "`")
            }.joined(separator: " && ")
            hashing = (includingPublicState ? "hasher.combine(state)\n" : "")
                + fields.map { hash($0.type, "self.`" + $0.name + "`", into: "hasher") }.joined(separator: "\n")
        } else {
            func pattern(_ name: String, _ types: [CompiledValueType], _ prefix: String) -> String {
                "." + name + (types.isEmpty ? "" : "(" + types.indices.map { "let \(prefix)\($0)" }.joined(separator: ", ") + ")")
            }
            equality = "switch (lhs, rhs) {\n" + cases.map { value in
                let comparisons = value.types.enumerated().map {
                    equal($0.element, "_lhs\($0.offset)", "_rhs\($0.offset)")
                }.joined(separator: " && ")
                return "case (\(pattern(value.name, value.types, "_lhs")), \(pattern(value.name, value.types, "_rhs"))): return \(comparisons.isEmpty ? "true" : comparisons)"
            }.joined(separator: "\n") + (cases.count > 1 ? "\ndefault: return false" : "") + "\n}"
            hashing = "switch self {\n" + cases.enumerated().map { offset, value in
                let payload = value.types.enumerated().map {
                    hash($0.element, "_value\($0.offset)", into: "hasher")
                }.joined(separator: "\n")
                return "case \(pattern(value.name, value.types, "_value")): hasher.combine(\(offset))\n\(payload)"
            }.joined(separator: "\n") + "\n}"
        }
        var equalityHelpers: [String] = []
        var hashHelpers: [String] = []
        var cursor = 0
        while cursor < types.count {
            let type = types[cursor]
            let equalityBody: String
            let hashBody: String
            if let members = type.recordFields {
                equalityBody = members.map {
                    "guard \(equal($0.type, "lhs.`" + $0.name + "`", "rhs.`" + $0.name + "`")) else { return false }"
                }.joined(separator: "\n") + "\nreturn true"
                hashBody = members.map { hash($0.type, "value.`" + $0.name + "`", into: "hasher") }.joined(separator: "\n")
            } else {
                switch type {
                case .named(let name):
                    let rank = "func rank(_ value: \(try swiftType(type))) -> \(nativeIntType) { switch value { \(try enumRankCases(name)) } }"
                    equalityBody = rank + "\nreturn rank(lhs) == rank(rhs)"
                    hashBody = rank + "\nhasher.combine(rank(value))"
                case .tuple(let elements):
                    equalityBody = elements.enumerated().map {
                        "guard \(equal($0.element, "lhs." + fieldName(type, index: $0.offset), "rhs." + fieldName(type, index: $0.offset))) else { return false }"
                    }.joined(separator: "\n") + "\nreturn true"
                    hashBody = elements.enumerated().map {
                        hash($0.element, "value." + fieldName(type, index: $0.offset), into: "hasher")
                    }.joined(separator: "\n")
                case .array(let element):
                    equalityBody = "return lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { pair in \(equal(element, "pair.0", "pair.1")) }"
                    hashBody = "hasher.combine(value.count); for element in value { \(hash(element, "element", into: "hasher")) }"
                case .set(let element):
                    equalityBody = """
                    guard lhs.count == rhs.count else { return false }
                    var remaining = rhs.map { $0 }
                    for a in lhs {
                        guard let index = remaining.firstIndex(where: { b in \(equal(element, "a", "b")) }) else { return false }
                        remaining.remove(at: index)
                    }
                    return true
                    """
                    hashBody = """
                    var unorderedHash = 0
                    for element in value {
                        var memberHasher = \(hasherType)()
                        \(hash(element, "element", into: "memberHasher"))
                        unorderedHash ^= memberHasher.finalize()
                    }
                    hasher.combine(value.count)
                    hasher.combine(unorderedHash)
                    """
                case .dictionary(let key, let value):
                    equalityBody = """
                    guard lhs.count == rhs.count else { return false }
                    var remaining = rhs.map { $0 }
                    for a in lhs {
                        guard let index = remaining.firstIndex(where: { b in \(equal(key, "a.key", "b.key")) && \(equal(value, "a.value", "b.value")) }) else { return false }
                        remaining.remove(at: index)
                    }
                    return true
                    """
                    hashBody = """
                    var unorderedHash = 0
                    for entry in value {
                        var memberHasher = \(hasherType)()
                        \(hash(key, "entry.key", into: "memberHasher"))
                        \(hash(value, "entry.value", into: "memberHasher"))
                        unorderedHash ^= memberHasher.finalize()
                    }
                    hasher.combine(value.count)
                    hasher.combine(unorderedHash)
                    """
                case .oneOf, .union:
                    equalityBody = "switch (lhs, rhs) {\n" + type.unionAlternatives!.enumerated().map {
                        "case (.\(unionCase(type, index: $0.offset))(let a), .\(unionCase(type, index: $0.offset))(let b)): return \(equal($0.element, "a", "b"))"
                    }.joined(separator: "\n") + "\ndefault: return false\n}"
                    hashBody = "switch value {\n" + type.unionAlternatives!.enumerated().map {
                        "case .\(unionCase(type, index: $0.offset))(let payload): hasher.combine(\($0.offset)); \(hash($0.element, "payload", into: "hasher"))"
                    }.joined(separator: "\n") + "\n}"
                default: throw unsupported("record identity")
                }
            }
            let name = try swiftType(type)
            equalityHelpers.append("""
            func _identityEqual\(cursor)(_ lhs: \(name), _ rhs: \(name)) -> \(nativeBoolType) {
                \(equalityBody)
            }
            """)
            hashHelpers.append("""
            func _identityHash\(cursor)(_ value: \(name), into hasher: inout \(hasherType)) {
                \(hashBody)
            }
            """)
            cursor += 1
        }
        // shortcut: structural set/map equality scans members; use compiler-owned collection keys if profiling shows this dominates.
        return (equality: equalityHelpers.joined(separator: "\n") + "\n" + equality,
            hashing: hashHelpers.joined(separator: "\n") + "\n" + hashing)
    }

    func valueTypeDeclarations() throws -> [DeclSyntax] {
        var declarations: [DeclSyntax] = []
        var publicTypes: Set<CompiledValueType> = []
        var storedTypes: Set<CompiledValueType> = []
        var stored: [CompiledValueType] = []
        var pending: [CompiledValueType] = []
        var programs = [program]
        var visitedPrograms: Set<CompilationIdentity> = []
        while let source = programs.popLast() {
            guard visitedPrograms.insert(source.identity).inserted else { continue }
            let api = try GeneratedMachineAPI(layout: source.layout, actions: source.behavior.actions)
            pending += api.variables.compactMap { source.variableTypes[$0.id] }
            pending += source.layout.parameters.compactMap { source.bindingTypes[$0.binder] }
            pending += source.checkingRegisterTypes.values
            stored += source.variableTypes.values
            for action in api.actions {
                pending += zip(source[action.compiledAction].bindings, action.bindings).compactMap {
                    $0.1.isPublic ? source.bindingTypes[$0.0.binder] : nil
                }
            }
            programs += source.refinements.map(\.abstract)
        }
        while let type = pending.popLast() {
            guard publicTypes.insert(type).inserted else { continue }
            pending += type.components
        }
        while let type = stored.popLast() {
            guard storedTypes.insert(type).inserted else { continue }
            stored += type.components
        }
        func access(_ type: CompiledValueType) -> String {
            publicTypes.contains(type) ? "public " : storedTypes.contains(type) ? "" : "private "
        }
        for (index, element) in typeDeclarations.identityElements.enumerated() {
            var identityEmitter = self
            // The policy's Element alias must not capture a source enum named Element.
            identityEmitter.sourceNominalPrefix = model.typeName
            let bodies = try identityEmitter.structuralIdentityBodies(fields: [], cases: [], includingPublicState: false, value: element)
            let exposed = publicTypes.contains(element)
            let typeAccess = access(element)
            let memberAccess = exposed ? "public " : ""
            declarations += try nativeDeclarations("""
            @_documentation(visibility: internal)
            \(typeAccess)enum _SetIdentity\(index): SwiftTLA._NativeSetIdentity {
                \(memberAccess)typealias Element = \(try identityEmitter.swiftType(element))
                \(memberAccess)static func equal(_ lhs: Element, _ rhs: Element) -> \(nativeBoolType) {
                    \(bodies.equality)
                }
                \(memberAccess)static func hash(_ value: Element, into hasher: inout SwiftTLA._NativeMachineOperations.StateHasher) {
                    \(bodies.hashing)
                }
            }
            """)
        }
        let modelValues = typeDeclarations.modelValueCases.sorted { $0.key < $1.key }
        if !modelValues.isEmpty {
            declarations += try nativeDeclarations("""
            @_documentation(visibility: internal)
            public enum _ModelValue: \(nativeStringType), Hashable, Sendable {
                \(modelValues.map { "case \($0.value) = \(String(reflecting: $0.key))" }.joined(separator: "\n"))
            }
            """)
        }
        for (index, type) in typeDeclarations.unions.enumerated() {
            guard let alternatives = type.unionAlternatives else { throw unsupported("native union alternatives") }
            let typeAccess = access(type)
            let cases = try alternatives.enumerated().map {
                "case \(unionCase(type, index: $0.offset))(\(try swiftType($0.element)))"
            }.joined(separator: "\n")
            var value = try nativeDeclarations("""
            \(typeAccess)enum NativeUnion\(index): Hashable, Sendable {
                \(cases)
            }
            """)
            try addStructuralIdentity(to: &value, cases: alternatives.enumerated().map {
                (name: unionCase(type, index: $0.offset), types: [$0.element])
            })
            declarations += value
        }
        for (index, type) in typeDeclarations.records.enumerated() {
            let elements: [CompiledValueType]
            switch type {
            case .tuple(let items): elements = items
            case .record(let fields), .nominalRecord(_, let fields): elements = fields.map(\.type)
            default: throw unsupported("record declaration")
            }
            let memberAccess = publicTypes.contains(type) ? "public " : ""
            let fields = try elements.enumerated().map { "\(memberAccess)let \(fieldName(type, index: $0.offset)): \(try swiftType($0.element))" }.joined(separator: "\n")
            let parameters = try elements.enumerated().map { "\(fieldName(type, index: $0.offset)) _field\($0.offset): \(try swiftType($0.element))" }.joined(separator: ", ")
            let assignments = elements.indices.map { "self.\(fieldName(type, index: $0)) = _field\($0)" }.joined(separator: "\n")
            let typeAccess = access(type)
            var value = try nativeDeclarations("""
            \(typeAccess)struct NativeRecord\(index): Hashable, Sendable {
                \(fields)
                \(memberAccess)init(\(parameters)) { \(assignments) }
            }
            """)
            try addStructuralIdentity(to: &value, fields: elements.enumerated().map {
                (name: fieldName(type, index: $0.offset, escaped: false), type: $0.element)
            })
            declarations += value
        }
        for (index, members) in typeDeclarations.finiteValues.enumerated() {
            declarations += try nativeDeclarations("""
            public enum NativeValue\(index): Hashable, Sendable {
                \(members.indices.map { "case \(finiteCaseName(members, index: $0))" }.joined(separator: "\n"))
            }
            """)
        }
        return declarations
    }

    func actionDeclarations() throws -> [DeclSyntax] {
        var identityCases: [(name: String, types: [CompiledValueType])] = []
        let cases = try model.api.actions.map { api in
            let action = program[api.compiledAction]
            guard action.bindings.count == api.bindings.count else {
                throw unsupported("action binding layout")
            }
            let bindings = zip(action.bindings, api.bindings).filter { $0.1.isPublic }
            identityCases.append((name: api.swiftIdentifier,
                types: bindings.map { program.bindingTypes[$0.0.binder]! }))
            let parameters = try bindings.map { binding, apiBinding in
                "\(apiBinding.swiftIdentifier): \(try swiftType(program.bindingTypes[binding.binder]!))"
            }.joined(separator: ", ")
            return "case \(api.swiftIdentifier)" + (parameters.isEmpty ? "" : "(\(parameters))")
        }.joined(separator: "\n")
        var declarations = try nativeDeclarations("""
        public enum Action: Hashable, Sendable {
            \(cases)
        }
        """)
        try addStructuralIdentity(to: &declarations, cases: identityCases)
        return declarations
    }

    private func executionState(values: (VariableID) -> String) -> String {
        let publicFields = model.api.variables.map {
            "\($0.argumentLabel): \(values($0.id))"
        }.joined(separator: ", ")
        let privateFields = program.layout.variables.filter { stateMemberNames[$0.id] == nil }.map {
            ", \(variable($0.id)): \(values($0.id))"
        }.joined()
        return "Snapshot(state: State(\(publicFields))\(privateFields))"
    }

    func updateDeclarations() throws -> [DeclSyntax] {
        let fields = try program.layout.variables.map { "var \(variable($0.id)): \(try swiftType(program.variableTypes[$0.id]!))? = nil" }.joined(separator: "\n")
        let merges = try program.layout.variables.map { slot in
            let name = variable(slot.id)
            let type = program.variableTypes[slot.id]!
            if containsSourceNominal(type) {
                return """
                guard SwiftTLA._NativeMachineOperations.mergeUpdate(&result.\(name), other.\(name), equivalent: { lhs, rhs in
                    let _mergeEqual_\(name) = \(try structuralEquivalence(type))
                    return _mergeEqual_\(name)(lhs, rhs)
                }) else { return nil }
                """
            }
            return "guard SwiftTLA._NativeMachineOperations.mergeUpdate(&result.\(name), other.\(name)) else { return nil }"
        }.joined(separator: "\n")
        let updated = executionState { "\(variable($0)) ?? \(stateValue($0))" }
        let declarations = try nativeDeclarations("""
        private struct _Updates: Sendable {
            \(fields)
            func merging(_ other: Self) -> Self? {
                var result = self
                \(merges)
                return result
            }
            func applying(to state: Snapshot) -> Snapshot {
                \(updated)
            }
        }
        """)
        try verifyGeneratedUpdateMergeOutput(
            declarations.first, slots: program.layout.variables.map { variable($0.id) },
            recordTypes: Dictionary(uniqueKeysWithValues: try program.layout.variables.compactMap { slot -> (String, String)? in
                let type = program.variableTypes[slot.id]!
                return containsSourceNominal(type) ? (variable(slot.id), try swiftType(type)) : nil
            }))
        try verifyGeneratedUpdateApplyOutput(
            declarations.first,
            publicFields: model.api.variables.map {
                (label: $0.argumentLabel, field: $0.swiftIdentifier, slot: variable($0.id))
            },
            hiddenSlots: program.layout.variables.filter { stateMemberNames[$0.id] == nil }.map {
                variable($0.id)
            })
        return declarations
    }

    private func initialFailureBindingsSource(
        _ prefix: ArraySlice<(variable: VariableID, initialization: CompiledVariableInitialization)>
    ) throws -> String {
        let captures = prefix.map { variable($0.variable) }
        let entries = try prefix.map { entry in
            let value = try formalValue(variable(entry.variable), type: program.variableTypes[entry.variable]!)
            return ".init(token: SwiftTLA._nativeFormalProjectionToken(Self.__swifttlaFormalProjectionTokens, at: \(entry.variable.ordinal)), value: \(value))"
        }
        let capture = captures.isEmpty ? "" : "[" + captures.joined(separator: ", ") + "] in "
        return "{ \(capture)try SwiftTLA._nativeFormalProjection([\(entries.joined(separator: ", "))]) }"
    }

    private enum InitialScope {
        case selection(prefix: String, condition: String)
        case branch(prefix: String, variable: String, candidates: String)
    }

    private mutating func initialStateSource(arguments: String) throws -> (
        code: String, scopes: [InitialScope], loops: [String: String],
        candidates: [String: String], membership: [String: String]
    ) {
        var code = ""
        var scopes: [InitialScope] = []
        var expectedLoops: [String: String] = [:]
        var expectedCandidateSources: [String: String] = [:]
        var expectedMembershipSources: [String: String] = [:]
        for (index, initialization) in program.behavior.initializations.enumerated() {
            let type = program.variableTypes[initialization.variable]!
            let name = variable(initialization.variable)
            code += "evaluatingInitialBindings = \(try initialFailureBindingsSource(program.behavior.initializations.prefix(index)))\n"
            switch initialization.initialization {
            case .value(let expression):
                code += "evaluatingInitializerOrdinal = \(initialization.variable.ordinal)\n"
                code += "let \(name): \(try swiftType(type)) = \(try self.expression(expression, state: ""))\n"
                code += "evaluatingInitializerOrdinal = nil\n"
                if let field = stateMemberNames[initialization.variable] {
                    let condition: String
                    if type == .int {
                        condition = "SwiftTLA._nativeIntInitialMatches(_selectedInitial?.\(field), \(name))"
                    } else if containsSourceNominal(type) {
                        let order = "_initialValueOrder\(initialization.variable.ordinal)"
                        code += "let \(order) = \(try crossOrdering(type, type))\n"
                        condition = "_selectedInitial == nil || !(\(order)(_selectedInitial!.\(field), \(name)) || \(order)(\(name), _selectedInitial!.\(field)))"
                    } else {
                        condition = "_selectedInitial == nil || _selectedInitial!.\(field) == \(name)"
                    }
                    scopes.append(.selection(prefix: code, condition: condition))
                    code = ""
                }
            case .memberOf(let expression):
                code += "evaluatingInitializerOrdinal = \(initialization.variable.ordinal)\n"
                let randomSubsetOperands: (count: CompiledExpression, domain: CompiledExpression)?
                if case .randomSubset = expression.computation.operation {
                    randomSubsetOperands = (expression.computation.children[0], expression.computation.children[1])
                } else {
                    randomSubsetOperands = nil
                }
                if let operands = randomSubsetOperands {
                    code += "let \(name)_sampleLimit = \(try self.expression(operands.count, state: ""))\n"
                    code += "try SwiftTLA._NativeMachineOperations.validateRandomSubsetCount(\(name)_sampleLimit)\n"
                }
                let candidateSource: String
                if let operands = randomSubsetOperands {
                    let domain = try self.expression(operands.domain, state: "")
                    let sample: String
                    let exhaustive: String
                    if case .functionSet = operands.domain.operation,
                       case .set(.dictionary) = expression.computation.resultType {
                        let from = try self.expression(operands.domain.children[0], state: "")
                        let to = try self.expression(operands.domain.children[1], state: "")
                        let forming = containsSourceNominal(expression.computation.resultType)
                            ? ", forming: \(try swiftType(expression.computation.resultType)).self" : ""
                        sample = "try SwiftTLA._NativeMachineOperations.randomFunctionSubset(upTo: \(name)_sampleLimit, from: \(from), to: \(to)\(forming))"
                        exhaustive = "try SwiftTLA._NativeMachineOperations.randomFunctionInitialSupport(upTo: \(name)_sampleLimit, from: \(from), to: \(to)\(forming))"
                    } else {
                        sample = "try SwiftTLA._NativeMachineOperations.randomSubset(upTo: \(name)_sampleLimit, from: \(domain))"
                        exhaustive = "try SwiftTLA._NativeMachineOperations.randomSubsetInitialSupport(upTo: \(name)_sampleLimit, from: \(domain))"
                    }
                    candidateSource = "(_sampleRandomSubset ? (\(sample)) : (\(exhaustive))).sorted(by: \(try ordering(type)))"
                } else if let members = try nominalSetElements(expression, state: "") {
                    candidateSource = "\(members).sorted(by: \(try crossOrdering(type, type)))"
                } else {
                    candidateSource = "\(try self.expression(expression, state: "")).sorted(by: \(try ordering(type)))"
                }
                let candidates: String
                if let field = stateMemberNames[initialization.variable] {
                    let membershipDomain = randomSubsetOperands?.domain ?? expression
                    let membership = CompiledExpression(operation: .in, resultType: .bool, children: [
                        CompiledExpression(operation: .stateVariable(initialization.variable), resultType: type, children: []),
                        membershipDomain
                    ])
                    let eligible = randomSubsetOperands == nil
                        ? "\(name)_isMember"
                        : "\(name)_sampleLimit > 0 && \(name)_isMember"
                    let membershipSource = try self.expression(membership, state: "")
                    expectedLoops[name] = "\(name)Candidates"
                    expectedCandidateSources["\(name)Candidates"] = candidateSource
                    expectedMembershipSources[name] = membershipSource
                    code += """
                    let \(name)Candidates: [\(try swiftType(type))] = try SwiftTLA._NativeMachineOperations.initialCandidates(
                        selecting: _selectedInitial.map(\\.\(field)),
                        enumerate: { \(candidateSource) },
                        contains: { \(name) in
                        let \(name)_isMember = \(membershipSource)
                        return \(eligible)
                        }
                    )
                    """
                    candidates = "\(name)Candidates"
                } else {
                    expectedLoops[name] = candidateSource
                    candidates = candidateSource
                }
                scopes.append(.branch(prefix: code, variable: name, candidates: candidates))
                code = ""
            }
        }
        if let selected = program.behavior.initialInvariant {
            let arguments = arguments.isEmpty ? "" : ", " + arguments
            code += "evaluatingInitialBindings = \(try initialFailureBindingsSource(program.behavior.initializations[...]))\n"
            code += "let candidate = \(executionState(values: variable))\n"
            code += "if try Self._invariant\(selected.ordinal)(in: candidate, atLevel: 0\(arguments)) { SwiftTLA._appendNativeOutcome(&result, candidate) }\n"
        } else {
            code += "SwiftTLA._appendNativeOutcome(&result, \(executionState(values: variable)))\n"
        }
        return (code, scopes, expectedLoops, expectedCandidateSources, expectedMembershipSources)
    }

    private func initialBranch(_ body: CodeBlockItemListSyntax) throws -> CodeBlockItemSyntax {
        let parsed = Parser.parse(source: """
        try SwiftTLA._visitNativeInitialBranch({}, onEvaluationFailure: { failure in
            SwiftTLA._appendNativeOutcome(&failures, .init(
                site: SwiftTLA._nativeInitialFailureSite(evaluatingInitializerOrdinal),
                failure: failure, projectingBefore: evaluatingInitialBindings))
        })
        """)
        guard var item = parsed.statements.first,
              var attempt = item.item.as(TryExprSyntax.self),
              var call = attempt.expression.as(FunctionCallExprSyntax.self),
              var argument = call.arguments.first,
              var closure = argument.expression.as(ClosureExprSyntax.self) else {
            throw unsupported("initial branch declaration")
        }
        closure.statements = body
        argument.expression = ExprSyntax(closure)
        call.arguments[call.arguments.startIndex] = argument
        attempt.expression = ExprSyntax(call)
        item.item = .expr(ExprSyntax(attempt))
        return item
    }

    private func initialBody(_ source: String, scopes: [InitialScope]) throws -> CodeBlockItemListSyntax {
        var body = Parser.parse(source: source).statements
        for scope in scopes.reversed() {
            let prefix: String
            let statement: CodeBlockItemSyntax
            switch scope {
            case .selection(let source, let condition):
                prefix = source
                let selection = try IfExprSyntax("if \(raw: condition)") { body }
                statement = CodeBlockItemSyntax(item: .expr(ExprSyntax(selection)))
            case .branch(let source, let variable, let candidates):
                prefix = source
                let branch = try initialBranch(body).with(\.leadingTrivia, .newlines(1))
                let loop = try ForStmtSyntax("for \(raw: variable) in \(raw: candidates)") {
                    ExprSyntax("evaluatingInitializerOrdinal = nil")
                    branch
                }
                statement = CodeBlockItemSyntax(item: .stmt(StmtSyntax(loop)))
            }
            body = CodeBlockItemListSyntax(Array(Parser.parse(source: prefix).statements)
                + [statement.with(\.leadingTrivia, .newlines(1))])
        }
        return body
    }

    mutating func initialDeclarations(parameters: String, arguments: String) throws -> [DeclSyntax] {
        let source = try initialStateSource(arguments: arguments)
        let hasRandomSubset = hasRandomSubsetInitializer
        let appendedParameters = parameters.isEmpty ? "" : ", " + parameters
        let appendedArguments = arguments.isEmpty ? "" : ", " + arguments
        let samplingParameter = hasRandomSubset ? ", _sampleRandomSubset: \(nativeBoolType) = false" : ""
        let unselectedArguments = "_selectedInitial: nil as State?\(hasRandomSubset ? ", _sampleRandomSubset: false" : "")\(appendedArguments)"
        let body = try initialBody(source.code, scopes: source.scopes)
        let prefix = Parser.parse(source: """
        var result: [Snapshot] = []
        var failures: [SwiftTLA.InitialEvaluationFailure] = []
        var evaluatingInitializerOrdinal: \(nativeIntType)?
        var evaluatingInitialBindings: @Sendable () throws -> SwiftTLA.TLAStateProjection = { try SwiftTLA._nativeFormalProjection([]) }
        """).statements
        let branch = try initialBranch(body).with(\.leadingTrivia, .newlines(1))
        let returning = Parser.parse(source: "return SwiftTLA._nativeInitialOutcomes(states: result, failures: failures)")
            .statements.map { $0.with(\.leadingTrivia, .newlines(1)) }
        let statements = CodeBlockItemListSyntax(Array(prefix) + [branch] + returning)
        let initial = try FunctionDeclSyntax("private static func _initialStates(_selectedInitial: State? = nil\(raw: samplingParameter)\(raw: appendedParameters)) throws -> SwiftTLA.InitialEvaluationOutcomes<Snapshot>") {
            statements
        }
        var declarations = [DeclSyntax(initial)]
        declarations += try nativeDeclarations("""
        private static func _completedInitialStates(_selectedInitial: State? = nil\(samplingParameter)\(appendedParameters)) throws -> [Snapshot] {
            let outcome: SwiftTLA.InitialEvaluationOutcomes<Snapshot> = try Self._initialStates(_selectedInitial: _selectedInitial\(hasRandomSubset ? ", _sampleRandomSubset: _sampleRandomSubset" : "")\(appendedArguments))
            return try SwiftTLA._completeNativeInitialOutcomes(outcome)
        }
        public static func initialOutcomes(\(parameters)) throws -> SwiftTLA.InitialEvaluationOutcomes<Self> {
            let outcome: SwiftTLA.InitialEvaluationOutcomes<Snapshot> = try Self._initialStates(\(unselectedArguments))
            return SwiftTLA._mapNativeInitialOutcomes(outcome) { Self(execution: $0\(appendedArguments)) }
        }
        public static func initialMachines(\(parameters)) throws -> [Self] {
            SwiftTLA._mapNativeOutcomes(try Self._completedInitialStates(\(unselectedArguments)) as [Snapshot]) { Self(execution: $0\(appendedArguments)) }
        }
        public static func makeMachine(\(parameters)) throws -> Self {
            let execution = try SwiftTLA._singleNativeOutcome(
                Self._completedInitialStates(\(unselectedArguments)) as [Snapshot], missing: .noInitialState, ambiguous: .ambiguousInitialState)
            return Self(execution: execution\(appendedArguments))
        }
        public static func makeMachine(_ initial: State\(appendedParameters)) throws -> Self {
            let execution = try SwiftTLA._singleNativeOutcome(
                Self._completedInitialStates(_selectedInitial: initial as State?\(hasRandomSubset ? ", _sampleRandomSubset: false" : "")\(appendedArguments)) as [Snapshot], missing: .invalidInitialState, ambiguous: .ambiguousInitialState)
            return Self(execution: execution\(appendedArguments))
        }
        """)
        if hasRandomSubset {
            declarations += try nativeDeclarations("""
            public static func sampledInitialMachines(\(parameters)) throws -> [Self] {
                SwiftTLA._mapNativeOutcomes(try Self._completedInitialStates(_selectedInitial: nil as State?, _sampleRandomSubset: true\(appendedArguments)) as [Snapshot]) { Self(execution: $0\(appendedArguments)) }
            }
            """)
        }
        try verifyInitialDeclarations(declarations, expectedLoops: source.loops,
            expectedCandidateSources: source.candidates, expectedMembershipSources: source.membership,
            hasRandomSubset: hasRandomSubset)
        if hasRandomSubset {
            declarations += try selectedInitialDeclarations(arguments: arguments)
        }
        return declarations
    }

    private func verifyInitialDeclarations(
        _ declarations: [DeclSyntax], expectedLoops: [String: String],
        expectedCandidateSources: [String: String], expectedMembershipSources: [String: String],
        hasRandomSubset: Bool
    ) throws {
        let initialSlots = Dictionary(uniqueKeysWithValues: program.layout.variables.map {
            ($0.id, variable($0.id))
        })
        try verifyGeneratedInitialBindings(
            declarations.first { $0.as(FunctionDeclSyntax.self)?.name.text == "_initialStates" },
            expected: program.behavior.initializations.map { initialization in
                let name = variable(initialization.variable)
                switch initialization.initialization {
                case .value: return "let \(name)"
                case .memberOf: return "for \(name)"
                }
            }, expectedLoops: expectedLoops, expectedCandidateSources: expectedCandidateSources,
            expectedIntLiterals: Dictionary(uniqueKeysWithValues:
                program.behavior.initializations.compactMap { initialization -> (String, Int)? in
                    guard case .value(let expression) = initialization.initialization,
                          case .value(.integer(let value)) = expression.operation,
                          expression.resultType == .int else { return nil }
                    return (variable(initialization.variable), value)
                }),
            expectedControlLocations: Dictionary(uniqueKeysWithValues:
                program.behavior.initializations.compactMap { initialization -> (String, Int)? in
                    guard case .value(let expression) = initialization.initialization,
                          case .controlLocation(let id) = expression.operation,
                          expression.resultType == .controlLocation else { return nil }
                    return (variable(initialization.variable), id.ordinal)
                }),
            expectedIntExpressions: Dictionary(uniqueKeysWithValues:
                program.behavior.initializations.compactMap { initialization -> (String, CompiledExpression)? in
                    guard case .value(let expression) = initialization.initialization,
                          expression.resultType == .int,
                          checkedIntInitialValue(expression, slots: initialSlots) != nil else { return nil }
                    if case .value(.integer) = expression.operation { return nil }
                    return (variable(initialization.variable), expression)
                }),
            stateSlots: initialSlots)
        try verifyRandomSubsetInitialSupport(declarations.first,
            expected: program.behavior.initializations.compactMap { initialization -> (String, Bool)? in
                guard case .memberOf(let expression) = initialization.initialization,
                      case .randomSubset = expression.computation.operation else { return nil }
                let domain = expression.computation.children[1]
                if case .functionSet = domain.operation { return (variable(initialization.variable), true) }
                return (variable(initialization.variable), false)
            })
        try verifyInitialSelection(declarations.first, expectedMembershipSources: expectedMembershipSources)
        try verifyInitialStateAssembly(declarations.first)
        try verifyIntInitialOutput(declarations.first)
        try verifyGeneratedInitialConstruction(declarations, configured: !program.layout.parameters.isEmpty,
            sampled: hasRandomSubset)
    }

    func verifyInitialSelection(
        _ declaration: DeclSyntax?, expectedMembershipSources: [String: String]
    ) throws {
        let tokens = declaration.map { Array($0.tokens(viewMode: .sourceAccurate)).map(\.text) } ?? []
        func occursOnce(_ source: String) -> Bool {
            let pattern = Array(Parser.parse(source: source).tokens(viewMode: .sourceAccurate))
                .map(\.text).filter { !$0.isEmpty }
            guard !pattern.isEmpty, tokens.count >= pattern.count else { return false }
            return (0...(tokens.count - pattern.count)).filter {
                tokens[$0..<($0 + pattern.count)].elementsEqual(pattern)
            }.count == 1
        }
        for initialization in program.behavior.initializations {
            guard let field = stateMemberNames[initialization.variable] else { continue }
            let name = variable(initialization.variable)
            let required: [String]
            switch initialization.initialization {
            case .value:
                let type = program.variableTypes[initialization.variable]!
                if type == .int {
                    required = ["if SwiftTLA._nativeIntInitialMatches(_selectedInitial?.\(field), \(name)) {"]
                } else if containsSourceNominal(type) {
                    let order = "_initialValueOrder\(initialization.variable.ordinal)"
                    required = [
                        "let \(order) = { (lhs: \(try swiftType(type)), rhs: \(try swiftType(type))) -> \(nativeBoolType) in",
                        "if _selectedInitial == nil || !(\(order)(_selectedInitial!.\(field), \(name)) || \(order)(\(name), _selectedInitial!.\(field))) {",
                    ]
                } else {
                    required = ["if _selectedInitial == nil || _selectedInitial!.\(field) == \(name) {"]
                }
            case .memberOf(let expression):
                let eligible: String
                if case .randomSubset = expression.computation.operation {
                    eligible = "\(name)_sampleLimit > 0 && \(name)_isMember"
                } else {
                    eligible = "\(name)_isMember"
                }
                let type = program.variableTypes[initialization.variable]!
                required = [
                    "let \(name)Candidates: [\(try swiftType(type))] = try SwiftTLA._NativeMachineOperations.initialCandidates(",
                    "selecting: _selectedInitial.map(\\.\(field))",
                    "contains: { \(name) in",
                    "return \(eligible)",
                ]
            }
            if let missing = required.first(where: { !occursOnce($0) }) {
                throw CompilationDiagnostic(
                    code: .unsupportedGeneratedValueShape, stage: .validation,
                    path: "native._initialStates.selection.\(name)",
                    expected: "one selected-initial guard and candidate filter for \(field)",
                    actual: "missing or repeated generated fragment: \(missing.prefix(160))",
                    nextSafeAction: "Report this native code generation failure."
                )
            }
            if case .memberOf = initialization.initialization {
                guard let membershipSource = expectedMembershipSources[name] else {
                    throw CompilationDiagnostic(code: .unsupportedGeneratedValueShape, stage: .validation,
                        path: "native._initialStates.selection.\(name)",
                        expected: "a compiled membership expression for \(field)", actual: "missing membership source",
                        nextSafeAction: "Report this native code generation failure.")
                }
                let fragment = "let \(name)_isMember = \(membershipSource)"
                let matches = declaration?.description.contains(fragment) == true
                guard matches else {
                    throw CompilationDiagnostic(code: .unsupportedGeneratedValueShape, stage: .validation,
                        path: "native._initialStates.selection.\(name)",
                        expected: "one exact compiled membership expression for \(field)",
                        actual: "generated membership expression differs from the compiled source",
                        nextSafeAction: "Report this native code generation failure.")
                }
            }
        }
    }

    func verifyInitialStateAssembly(_ declaration: DeclSyntax?) throws {
        let publicFields = model.api.variables.map {
            "\($0.argumentLabel): \(variable($0.id))"
        }.joined(separator: ", ")
        let hiddenFields = program.layout.variables.filter { stateMemberNames[$0.id] == nil }.map {
            ", \(variable($0.id)): \(variable($0.id))"
        }.joined()
        let state = "Snapshot(state: State(\(publicFields))\(hiddenFields))"
        let append: String
        if let invariant = program.behavior.initialInvariant {
            let configuration = program.layout.parameters.isEmpty ? "" : ", configuration: configuration"
            append = """
            evaluatingInitialBindings = \(try initialFailureBindingsSource(program.behavior.initializations[...]))
            let candidate = \(state)
            if try Self._invariant\(invariant.ordinal)(in: candidate, atLevel: 0\(configuration)) { SwiftTLA._appendNativeOutcome(&result, candidate) }
            """
        } else {
            append = "SwiftTLA._appendNativeOutcome(&result, \(state))"
        }
        let closing = program.behavior.initializations.reversed().map { initialization -> String in
            switch initialization.initialization {
            case .memberOf:
                return """
                }, onEvaluationFailure: { failure in
                    SwiftTLA._appendNativeOutcome(&failures, .init(
                        site: SwiftTLA._nativeInitialFailureSite(evaluatingInitializerOrdinal),
                        failure: failure, projectingBefore: evaluatingInitialBindings))
                })
                }

                """
            case .value:
                return stateMemberNames[initialization.variable] == nil ? "" : "}\n"
            }
        }.joined()
        let suffix = append + "\n" + closing + """
        }, onEvaluationFailure: { failure in
            SwiftTLA._appendNativeOutcome(&failures, .init(
                site: SwiftTLA._nativeInitialFailureSite(evaluatingInitializerOrdinal),
                failure: failure, projectingBefore: evaluatingInitialBindings))
        })
        return SwiftTLA._nativeInitialOutcomes(states: result, failures: failures)
        }
        """
        let expected = Array(Parser.parse(source: suffix).tokens(viewMode: .sourceAccurate))
            .map(\.text).filter { !$0.isEmpty }
        let actual = declaration.map { Array($0.tokens(viewMode: .sourceAccurate)).map(\.text) } ?? []
        guard expected.count <= actual.count, actual.suffix(expected.count).elementsEqual(expected) else {
            throw CompilationDiagnostic(
                code: .unsupportedGeneratedValueShape, stage: .validation,
                path: "native._initialStates.assembly",
                expected: "one complete compiled-state append, optional selected invariant, and return",
                actual: "the generated initial-state suffix differs from the checked assembly rule",
                nextSafeAction: "Report this native code generation failure."
            )
        }
    }

    func verifyIntInitialOutput(_ declaration: DeclSyntax?) throws {
        guard let source = try intInitialOutputSource(declaration) else { return }
        // Template lines have complete lexemes; parse them separately to avoid recursive closure nesting.
        let expectedTokens = source.split(separator: "\n").flatMap { line in
            Parser.parse(source: String(line)).tokens(viewMode: .sourceAccurate)
                .filter { $0.tokenKind != .endOfFile }
        }
        let actualTokens = declaration.map { Array($0.tokens(viewMode: .sourceAccurate)) } ?? []
        func sameToken(_ actual: TokenSyntax, _ expected: TokenSyntax) -> Bool {
            guard actual.text.utf8.elementsEqual(expected.text.utf8) else { return false }
            if actual.tokenKind == expected.tokenKind { return true }
            // Fragment parsing can leave generic angle delimiters classified as operators.
            switch (actual.tokenKind, expected.tokenKind) {
            case (.leftAngle, .binaryOperator), (.leftAngle, .prefixOperator),
                 (.leftAngle, .postfixOperator), (.rightAngle, .binaryOperator),
                 (.rightAngle, .prefixOperator), (.rightAngle, .postfixOperator),
                 (.binaryOperator, .leftAngle), (.prefixOperator, .leftAngle),
                 (.postfixOperator, .leftAngle), (.binaryOperator, .rightAngle),
                 (.prefixOperator, .rightAngle), (.postfixOperator, .rightAngle):
                return true
            default: return false
            }
        }
        guard declaration?.is(FunctionDeclSyntax.self) == true,
              actualTokens.elementsEqual(expectedTokens, by: sameToken) else {
            let detail = zip(actualTokens, expectedTokens).enumerated()
                .first { !sameToken($0.element.0, $0.element.1) }
                .map { "token \($0.offset): expected \($0.element.1.tokenKind), actual \($0.element.0.tokenKind)" }
                ?? "token counts: expected \(expectedTokens.count), actual \(actualTokens.count)"
            throw intInitialOutputMismatch(actual: detail)
        }
        let slots = Dictionary(uniqueKeysWithValues: program.layout.variables.map {
            ($0.id, variable($0.id))
        })
        for initialization in program.behavior.initializations {
            guard case .value(let expression) = initialization.initialization,
                  expression.resultType == .int else { continue }
            try verifyOrderedIntInitialExpression(declaration,
                named: variable(initialization.variable), expression: expression, slots: slots)
        }
    }

    private func intInitialOutputMismatch(
        actual: String = "the generated initial function contains an unrecognized statement or changed value"
    ) -> CompilationDiagnostic {
        CompilationDiagnostic(code: .unsupportedGeneratedValueShape, stage: .validation,
            path: "native._initialStates.completeIntOutput",
            expected: "the complete ordered Int initial-state and failure template",
            actual: actual,
            nextSafeAction: "Report this native initialization generation failure.")
    }

    private func intInitialOutputSource(_ declaration: DeclSyntax?) throws -> String? {
        // shortcut: other domain/child operations, configuration and invariant selection need their own rules.
        guard program.layout.parameters.isEmpty, program.behavior.initialInvariant == nil,
              program.behavior.initializations.count == program.layout.variables.count else { return nil }
        var bindings: [(name: String, type: String, value: String)] = []
        let slots = Dictionary(uniqueKeysWithValues: program.layout.variables.map {
            ($0.id, variable($0.id))
        })
        for initialization in program.behavior.initializations {
            let value: String
            let type: String
            switch initialization.initialization {
            case .value(let expression):
                switch (expression.operation, expression.resultType) {
                case (.value(.integer(let integer)), .int):
                    type = nativeIntType
                    value = integer == Int.min ? "\(nativeIntType).min" : String(integer)
                case (.controlLocation(let location), .controlLocation):
                    type = "_ControlLocation"
                    value = "_ControlLocation.location\(location.ordinal)"
                case (_, .int):
                    guard let checked = checkedIntInitialValue(expression, slots: slots) else { return nil }
                    type = nativeIntType
                    value = checked
                default: return nil
                }
            case .memberOf(let domain):
                guard program.variableTypes[initialization.variable] == .int,
                      domain.resultType == .set(.int),
                      let checked = checkedIntInitialDomainValue(domain, slots: slots) else { return nil }
                type = nativeIntType
                value = checked
            }
            bindings.append((variable(initialization.variable), type, value))
        }
        let actualTokens = declaration.map { Array($0.tokens(viewMode: .sourceAccurate)).map(\.text) } ?? []
        let predicatePrefix = "_membershipPredicate"
        let predicateNames = actualTokens.indices.compactMap { index -> String? in
            guard actualTokens[index] == "func", index + 1 < actualTokens.count,
                  actualTokens[index + 1].hasPrefix(predicatePrefix) else { return nil }
            return actualTokens[index + 1]
        }
        guard Set(predicateNames).count == predicateNames.count,
              predicateNames.allSatisfy({ name in
                  Int(name.dropFirst(predicatePrefix.count)).map { $0 >= 0 } == true
              }) else { throw intInitialOutputMismatch() }
        var nextPredicate = 0
        let visible = Dictionary(uniqueKeysWithValues: model.api.variables.map {
            ($0.id, $0.swiftIdentifier)
        })
        let publicFields = model.api.variables.map {
            "\($0.argumentLabel): \(variable($0.id))"
        }.joined(separator: ", ")
        let hiddenFields = program.layout.variables.filter { visible[$0.id] == nil }.map {
            ", \(variable($0.id)): \(variable($0.id))"
        }.joined()
        var body = "var result: [Snapshot] = []\nvar failures: [SwiftTLA.InitialEvaluationFailure] = []\nvar evaluatingInitializerOrdinal: \(nativeIntType)?\nvar evaluatingInitialBindings: @Sendable () throws -> SwiftTLA.TLAStateProjection = { try SwiftTLA._nativeFormalProjection([]) }\n"
        body += "try SwiftTLA._visitNativeInitialBranch({\n"
        var closing = ""
        for (index, pair) in zip(program.behavior.initializations, bindings).enumerated() {
            let (initialization, binding) = pair
            let prefix = zip(program.behavior.initializations, bindings).prefix(index)
            let captures = prefix.map { $0.1.name }
            let entries = prefix.map { prior, binding -> String in
                let value: String
                if binding.type == nativeIntType {
                    value = "SwiftTLA._nativeFormalInt(\(binding.name))"
                } else {
                    let cases = program.layout.controlLocations.map {
                        "case .location\($0.id.ordinal): return .string(\(String(reflecting: $0.formalName)))"
                    }.joined(separator: "\n")
                    value = "try { () throws -> SwiftTLA.TLAValue in switch \(binding.name) {\n\(cases)\n} }()"
                }
                return ".init(token: SwiftTLA._nativeFormalProjectionToken(Self.__swifttlaFormalProjectionTokens, at: \(prior.variable.ordinal)), value: \(value))"
            }
            let capture = captures.isEmpty ? "" : "[" + captures.joined(separator: ", ") + "] in "
            body += "evaluatingInitialBindings = { \(capture)try SwiftTLA._nativeFormalProjection([\(entries.joined(separator: ", "))]) }\n"
            body += "evaluatingInitializerOrdinal = \(initialization.variable.ordinal)\n"
            switch initialization.initialization {
            case .value:
                body += "let \(binding.name): \(binding.type) = \(binding.value)\n"
                body += "evaluatingInitializerOrdinal = nil\n"
                if let field = visible[initialization.variable] {
                    let condition = binding.type == nativeIntType
                        ? "SwiftTLA._nativeIntInitialMatches(_selectedInitial?.\(field), \(binding.name))"
                        : "_selectedInitial == nil || _selectedInitial!.\(field) == \(binding.name)"
                    body += "if \(condition) {\n"
                    closing = "}\n" + closing
                }
            case .memberOf(let domain):
                let ordered = "\(binding.value).sorted(by: { (lhs: \(nativeIntType), rhs: \(nativeIntType)) -> \(nativeBoolType) in\nreturn lhs < rhs\n})"
                if let field = visible[initialization.variable] {
                    guard let membership = checkedIntInitialDomainMembership(domain, candidate: binding.name,
                        slots: slots, predicateNames: predicateNames, nextPredicate: &nextPredicate) else {
                        throw intInitialOutputMismatch()
                    }
                    body += """
                    let \(binding.name)Candidates: [\(nativeIntType)] = try SwiftTLA._NativeMachineOperations.initialCandidates(
                        selecting: _selectedInitial.map(\\.\(field)),
                        enumerate: { \(ordered) },
                        contains: { \(binding.name) in
                        let \(binding.name)_isMember = \(membership)
                        return \(binding.name)_isMember
                        }
                    )
                    for \(binding.name) in \(binding.name)Candidates {

                    """
                } else {
                    body += "for \(binding.name) in \(ordered) {\n"
                }
                body += "evaluatingInitializerOrdinal = nil\ntry SwiftTLA._visitNativeInitialBranch({\n"
                closing = """
                }, onEvaluationFailure: { failure in
                    SwiftTLA._appendNativeOutcome(&failures, .init(
                        site: SwiftTLA._nativeInitialFailureSite(evaluatingInitializerOrdinal),
                        failure: failure, projectingBefore: evaluatingInitialBindings))
                })
                }

                """ + closing
            }
        }
        body += "SwiftTLA._appendNativeOutcome(&result, Snapshot(state: State(\(publicFields))\(hiddenFields)))\n" + closing
        body += """
        }, onEvaluationFailure: { failure in
            SwiftTLA._appendNativeOutcome(&failures, .init(
                site: SwiftTLA._nativeInitialFailureSite(evaluatingInitializerOrdinal),
                failure: failure, projectingBefore: evaluatingInitialBindings))
        })
        return SwiftTLA._nativeInitialOutcomes(states: result, failures: failures)
        """
        guard nextPredicate == predicateNames.count else { throw intInitialOutputMismatch() }
        return """
        private static func _initialStates(_selectedInitial: State? = nil) throws -> SwiftTLA.InitialEvaluationOutcomes<Snapshot> {
            \(body)
        }
        """
    }

    private func selectedInitialDeclarations(arguments: String) throws -> [DeclSyntax] {
        let decoded = try program.layout.variables.enumerated().compactMap { index, variable -> String? in
            guard stateMemberNames[variable.id] != nil else { return nil }
            let type = program.variableTypes[variable.id]!
            return """
            guard let _json\(index) = formalJSON.value(for: SwiftTLA._nativeFormalProjectionToken(Self.__swifttlaFormalProjectionTokens, at: \(index))) else {
                throw TLAStateProjectionDiagnostic.invalidKey(path: \(String(reflecting: variable.formalName)))
            }
            let _decoded\(variable.id.ordinal): \(try swiftType(type)) = \(try formalJSONValue("_json\(index)", type: type))
            """
        }.joined(separator: "\n")
        let fields = model.api.variables.map { "\($0.swiftIdentifier): _decoded\($0.id.ordinal)" }.joined(separator: ", ")
        let appendedArguments = arguments.isEmpty ? "" : ", \(arguments)"
        return try nativeDeclarations("""
        @_documentation(visibility: internal)
        public func selectedInitialMachine(from formalJSON: TLAJSONStateProjection) throws -> Self? {
            guard formalJSON.count == \(program.layout.variables.count) else { return nil }
            do {
                \(decoded)
                return try Self.makeMachine(State(\(fields))\(appendedArguments))
            } catch is TLAStateProjectionDiagnostic {
                return nil
            } catch GeneratedMachineError.invalidInitialState {
                return nil
            }
        }
        """)
    }

    mutating func actionFunctions(_ root: CompiledActionExpr) throws -> (
        source: String, writes: [(id: Int, slot: String, value: String)],
        conditions: [(id: Int, value: String)]
    ) {
        var pending: [(node: CompiledActionExpr, id: Int, bindings: [BinderID])] = [(root, 0, [])]
        var nextID = 1
        var declarations: [String] = []
        var writes: [(id: Int, slot: String, value: String)] = []
        var conditions: [(id: Int, value: String)] = []
        while let (node, id, bindings) = pending.popLast() {
            func childCall(_ child: CompiledActionExpr, binding: BinderID? = nil,
                           updates: String = "updates", emit: String = "emit") -> String {
                let childBindings = bindings + (binding.map { [$0] } ?? [])
                let childID = nextID
                nextID += 1
                pending.append((child, childID, childBindings))
                let arguments = childBindings.map(binder) + [updates, emit]
                return "try _actionPart\(childID)(\(arguments.joined(separator: ", ")))"
            }
            let body: String
            switch node {
            case .assign(let variableID, let value):
                let slot = variable(variableID)
                let evaluated = try expression(value)
                body = "if let merged = updates.merging(_Updates(\(slot): \(evaluated))) { try emit(merged) }"
                writes.append((id: id, slot: slot, value: evaluated))
            case .unchanged(let variableID):
                let slot = variable(variableID)
                let value = stateValue(variableID)
                body = "if let merged = updates.merging(_Updates(\(slot): \(value))) { try emit(merged) }"
                let expectedRead = stateMemberNames[variableID].map { "state.state.\($0)" } ?? "state.\(slot)"
                writes.append((id: id, slot: slot, value: expectedRead))
            case .guard_(let predicate):
                if let constant = predicate.booleanConstant {
                    body = constant ? "try emit(updates)" : "return"
                } else {
                    body = "guard \(try expression(predicate)) else { return }\ntry emit(updates)"
                }
            case .existsAction(let binding, let domainExpression, let child):
                let element = program.bindingTypes[binding]!
                let domain = try expression(domainExpression)
                body = """
                try SwiftTLA._NativeMachineOperations.visitAlternatives(\(domain).sorted(by: \(try ordering(element))), emit: emit) { \(binder(binding)), branchEmit in
                    \(childCall(child, binding: binding, emit: "branchEmit"))
                }
                """
            case .define(let binding, let value, let child):
                body = "let \(binder(binding)) = \(try expression(value))\n\(childCall(child, binding: binding))"
            case .ifElse(let condition, let yes, let no):
                let value = try expression(condition)
                body = """
                try SwiftTLA._NativeMachineOperations.visitConditional({ \(value) },
                    ifTrue: { \(childCall(yes)) },
                    ifFalse: { \(childCall(no)) })
                """
                conditions.append((id: id, value: value))
            case .and(let lhs, let rhs):
                let right = childCall(rhs, updates: "candidate")
                body = childCall(lhs, emit: "{ candidate in \(right) }")
            case .or(let lhs, let rhs):
                body = """
                try SwiftTLA._NativeMachineOperations.visitAlternatives([false, true], emit: emit) { second, branchEmit in
                    if second { \(childCall(rhs, emit: "branchEmit")) }
                    else { \(childCall(lhs, emit: "branchEmit")) }
                }
                """
            }
            let parameters = (try bindings.map {
                "_ \(binder($0)): \(try swiftType(program.bindingTypes[$0]!))"
            } + ["_ updates: _Updates", "_ emit: (_Updates) throws -> Void"]).joined(separator: ", ")
            let checkedBody: String
            if case .guard_(let predicate) = node, predicate.booleanConstant == false {
                checkedBody = body
            } else {
                checkedBody = """
                do {
                    \(body)
                } catch let failure as NativeMachineEvaluationError where failure.isModelEvaluationFailure {
                    failures.append(failure)
                }
                """
            }
            declarations.append("""
            func _actionPart\(id)(\(parameters)) throws {
                \(checkedBody)
            }
            """)
        }
        let failureBinding: String
        if case .guard_(let predicate) = root, predicate.booleanConstant == false {
            failureBinding = "let"
        } else {
            failureBinding = "var"
        }
        return ("""
            \(failureBinding) failures: [NativeMachineEvaluationError] = []
            func emit(_ update: _Updates) throws {
                do { try _emit(update) }
                catch { throw _StopSuccessorTraversal(cause: error) }
            }
            \(declarations.joined(separator: "\n"))
            do { try _actionPart0(_Updates(), emit) }
            catch let stop as _StopSuccessorTraversal {
                if let cause = stop.cause { throw cause }
                throw stop
            }
            return failures
            """,
            writes, conditions)
    }

    mutating func updateFunction(_ action: CompiledAction, configurationParameters: String) throws -> DeclSyntax {
        let previous = checkingContextName
        checkingContextName = "context"
        defer { checkingContextName = previous }
        let parameters = try action.bindings.map {
            "\(binder($0.binder)): \(try swiftType(program.bindingTypes[$0.binder]!))"
        }.joined(separator: ", ")
        let parts = try actionFunctions(action.body)
        let declaration = DeclSyntax(stringLiteral: """
        private static func _visitUpdates\(action.id.ordinal)(from state: Snapshot\(parameters.isEmpty ? "" : ", " + parameters)\(configurationParameters), checking context: inout CheckingContext<CheckingRegisters>?,
                                                   _ _emit: (_Updates) throws -> Void) throws -> [NativeMachineEvaluationError] {
            \(parts.source)
        }
        """)
        try verifyGeneratedActionWriteOutput(declaration, action: action.body, program: program,
            stateFields: stateMemberNames, parts: parts.writes, conditions: parts.conditions,
            requireScalarLeaves: isTotalScalarAssignment(action.body)
                || program.requiresOrderedIntOutput(action.id), externalBindings: action.bindings)
        return declaration
    }

    mutating func actionDomain(_ binding: CompiledActionBinding, state: String) throws -> String {
        if let members = try nominalSetElements(binding.domain, state: state) { return members }
        if let members = binding.literalMembers {
            return "[\(try members.map { try literal($0, as: program.bindingTypes[binding.binder]!) }.joined(separator: ", "))]"
        }
        return try expression(binding.domain, state: state)
    }

    mutating func enabledDeclarations(configurationParameters: String, configurationArguments: String) throws -> [DeclSyntax] {
        guard !enabledActionIDs.isEmpty else { return [] }
        var declarations: [DeclSyntax] = []
        for index in program.behavior.enabledActionIndices {
            let action = program.behavior.actions[index]
            guard enabledActionIDs.contains(action.id) else { continue }
            var loops = ""
            var closing = ""
            var arguments: [String] = []
            for binding in action.bindings {
                let name = binder(binding.binder)
                let domain = try actionDomain(binding, state: "state.")
                loops += "for \(name) in \(domain) {\n"
                closing += "}\n"
                arguments.append("\(name): \(name)")
            }
            declarations += try nativeDeclarations("""
            private static func _isEnabled\(action.id.ordinal)(in state: Snapshot\(configurationParameters)) throws -> \(nativeBoolType) {
                var context: CheckingContext<CheckingRegisters>?
                return try _isEnabled\(action.id.ordinal)(in: state\(configurationArguments), checking: &context)
            }
            private static func _isEnabled\(action.id.ordinal)(in state: Snapshot\(configurationParameters), checking context: inout CheckingContext<CheckingRegisters>?) throws -> \(nativeBoolType) {
                \(loops)
                var enabled = false
                let failures = try _visitUpdates\(action.id.ordinal)(from: state\(arguments.isEmpty ? "" : ", " + arguments.joined(separator: ", "))\(configurationArguments), checking: &context) { _ in enabled = true }
                if let failure = failures.first { throw failure }
                if enabled { return true }
                \(closing)
                return false
            }
            """)
        }
        return declarations
    }

    func successorFunction(_ action: CompiledAction, api: GeneratedMachineAPI.Action, configurationParameters: String, configurationArguments: String) throws -> DeclSyntax {
        let parameters = try action.bindings.map { binding in
            "\(binder(binding.binder)): \(try swiftType(program.bindingTypes[binding.binder]!))"
        }.joined(separator: ", ")
        let arguments = action.bindings.map { "\(binder($0.binder)): \(binder($0.binder))" }.joined(separator: ", ")
        let declaration = DeclSyntax(stringLiteral: """
        private static func _visitSuccessors\(action.id.ordinal)(from state: Snapshot\(parameters.isEmpty ? "" : ", " + parameters)\(configurationParameters), checking context: inout CheckingContext<CheckingRegisters>?,
                                                      _ visit: (Snapshot) throws -> Void) throws -> [NativeMachineEvaluationError] {
            var emitted: [Snapshot] = []
            return try _visitUpdates\(action.id.ordinal)(from: state\(arguments.isEmpty ? "" : ", " + arguments)\(configurationArguments), checking: &context) { updates in
                let candidate = updates.applying(to: state)
                if !emitted.contains(candidate) {
                    emitted.append(candidate)
                    try visit(candidate)
                }
            }
        }
        """)
        try verifyGeneratedSuccessorOutput(declaration, actionID: action.id.ordinal,
            parameters: parameters, arguments: arguments,
            configurationParameters: configurationParameters,
            configurationArguments: configurationArguments)
        return declaration
    }

    mutating func dispatchDeclarations(configurationArguments: String) throws -> [DeclSyntax] {
        guard !model.api.actions.isEmpty else {
            return try nativeDeclarations("""
            public func actionCandidates() throws -> [Action] { [] }
            public func enabledActions() throws -> [Action] { [] }
            public func successors() throws -> [(action: Action, machine: Self)] { [] }
            private func _successors(checking context: inout CheckingContext<CheckingRegisters>?) throws -> [(action: Action, machine: Self)] { [] }
            private func _visitSuccessors(checking context: inout CheckingContext<CheckingRegisters>?,
                                          _ visit: (Action, Self) throws -> \(nativeBoolType)) throws -> \(nativeBoolType) { false }
            private func _visitSuccessors(checking context: inout CheckingContext<CheckingRegisters>?,
                                          _ visit: (Action, Self) throws -> \(nativeBoolType),
                                          onEvaluationFailure: (Action, NativeMachineEvaluationError) throws -> \(nativeBoolType)) throws -> \(nativeBoolType) { false }
            public func formalCall(for action: Action) throws -> FormalActionCall {}
            """)
        }
        var visitorCases: [String] = []
        var formalCases: [String] = []
        var candidateEnumeration: [String] = []
        for api in model.api.actions {
            let action = program[api.compiledAction]
            var pattern: [String] = []
            var invocation: [String] = []
            var visitorValidations: [String] = []
            var actionArguments: [String] = []
            var formalArguments: [String] = []
            var loops = ""
            var closing = ""
            for (binding, apiBinding) in zip(action.bindings, api.bindings) {
                let name = binder(binding.binder)
                let type = program.bindingTypes[binding.binder]!
                let recordMembers = try nominalSetElements(binding.domain, state: "_execution.")
                let domain = try recordMembers ?? actionDomain(binding, state: "_execution.")
                if apiBinding.isPublic {
                    pattern.append("\(apiBinding.swiftIdentifier): let \(name)")
                    actionArguments.append("\(apiBinding.swiftIdentifier): \(name)")
                }
                let argumentValue: String
                if apiBinding.isPublic {
                    argumentValue = name
                } else {
                    guard let value = binding.literalMembers?.first else {
                        throw unsupported("a hidden action argument requires a literal singleton domain")
                    }
                    argumentValue = try literal(value, as: type)
                }
                formalArguments.append(try formalValue(argumentValue, type: type))
                if apiBinding.isPublic {
                    let membership: String
                    if recordMembers != nil {
                        let candidate = CompiledExpression(operation: .boundValue(binding.binder), resultType: type, children: [])
                        membership = try expression(.init(operation: .in, resultType: .bool, children: [candidate, binding.domain]),
                            state: "_execution.", substitutions: [binding.binder: name])
                    } else {
                        membership = "\(domain).contains(\(name))"
                    }
                    visitorValidations.append("guard \(membership) else { return [] }")
                    invocation.append("\(name): \(name)")
                    loops += "for \(name) in \(domain) {\n"
                    closing += "}\n"
                } else {
                    invocation.append("\(name): \(argumentValue)")
                }
            }
            let label = ".\(api.swiftIdentifier)" + (pattern.isEmpty ? "" : "(\(pattern.joined(separator: ", ")))")
            let formalName = program.layout.actions[action.id.ordinal].renderedName
            formalCases.append("case \(label): return FormalActionCall(name: \(String(reflecting: formalName)), arguments: [\(formalArguments.joined(separator: ", "))])")
            visitorCases.append("""
            case \(label):
                \(visitorValidations.joined(separator: "\n"))
                return try Self._visitSuccessors\(action.id.ordinal)(from: _execution\(invocation.isEmpty ? "" : ", " + invocation.joined(separator: ", "))\(configurationArguments), checking: &context, visit)
            """)
            let actionValue = ".\(api.swiftIdentifier)" + (actionArguments.isEmpty ? "" : "(\(actionArguments.joined(separator: ", ")))")
            candidateEnumeration.append("do {\n" + loops + "try visit(\(actionValue))\n" + closing + "}\n")
        }
        let declarations = try nativeDeclarations("""
        public func visitSuccessors(for action: Action, checking context: inout CheckingContext<CheckingRegisters>,
                                    _ visit: (Self) throws -> \(nativeBoolType)) throws -> \(nativeBoolType) {
            var run: CheckingContext<CheckingRegisters>? = context
            defer { context = run! }
            var found = false
            do {
                let failures = try _visitSuccessors(for: action, checking: &run) { execution in
                    found = true
                    if try !visit(Self(execution: execution\(configurationArguments))) {
                        throw _StopSuccessorTraversal()
                    }
                }
                if let failure = failures.first { throw failure }
            } catch is _StopSuccessorTraversal {
            }
            return found
        }
        public func formalCall(for action: Action) throws -> FormalActionCall {
            switch action {
                \(formalCases.joined(separator: "\n"))
            }
        }
        private func _successors(for action: Action) throws -> [Snapshot] {
            var context: CheckingContext<CheckingRegisters>?
            return try _successors(for: action, checking: &context)
        }
        private func _successors(for action: Action, checking context: inout CheckingContext<CheckingRegisters>?) throws -> [Snapshot] {
            var result: [Snapshot] = []
            let failures = try _visitSuccessors(for: action, checking: &context) { SwiftTLA._appendNativeOutcome(&result, $0) }
            if let failure = failures.first { throw failure }
            return result
        }
        private func _visitSuccessors(for action: Action, checking context: inout CheckingContext<CheckingRegisters>?,
                                      _ visit: (Snapshot) throws -> Void) throws -> [NativeMachineEvaluationError] {
            switch action {
                \(visitorCases.joined(separator: "\n"))
            }
        }
        public func isEnabled(_ action: Action) throws -> \(nativeBoolType) {
            try !_successors(for: action).isEmpty
        }
        public func successors(for action: Action) throws -> [Self] {
            try _successors(for: action).map { execution in
                return Self(execution: execution\(configurationArguments))
            }
        }
        private func _visitActionCandidates(_ visit: (Action) throws -> Void) throws {
            \(candidateEnumeration.joined(separator: "\n"))
        }
        private func _actions() throws -> [Action] {
            var result: [Action] = []
            try _visitActionCandidates { result.append($0) }
            return result
        }
        public func actionCandidates() throws -> [Action] { try _actions() }
        public func successors() throws -> [(action: Action, machine: Self)] {
            var context: CheckingContext<CheckingRegisters>?
            return try _successors(checking: &context)
        }
        private func _successors(checking context: inout CheckingContext<CheckingRegisters>?) throws -> [(action: Action, machine: Self)] {
            var result: [(action: Action, machine: Self)] = []
            _ = try _visitSuccessors(checking: &context) { action, machine in
                result.append((action, machine))
                return true
            }
            return result
        }
        private func _visitSuccessors(checking context: inout CheckingContext<CheckingRegisters>?,
                                      _ visit: (Action, Self) throws -> \(nativeBoolType)) throws -> \(nativeBoolType) {
            try _visitSuccessors(checking: &context, visit, onEvaluationFailure: { action, reason in
                throw MachineActionEvaluationFailure(action: action, reason: reason)
            })
        }
        private func _visitSuccessors(checking context: inout CheckingContext<CheckingRegisters>?,
                                      _ visit: (Action, Self) throws -> \(nativeBoolType),
                                      onEvaluationFailure: (Action, NativeMachineEvaluationError) throws -> \(nativeBoolType)) throws -> \(nativeBoolType) {
            var found = false
            do {
                func _visitAction(_ action: Action) throws {
                    var callbackFailed = false
                    var failures: [NativeMachineEvaluationError] = []
                    do {
                        failures = try _visitSuccessors(for: action, checking: &context) { execution in
                            found = true
                            do {
                                if try !visit(action, Self(execution: execution\(configurationArguments))) {
                                    throw _StopSuccessorTraversal()
                                }
                            } catch {
                                callbackFailed = true
                                throw error
                            }
                        }
                    } catch let reason as NativeMachineEvaluationError where !callbackFailed && reason.isModelEvaluationFailure {
                        failures.append(reason)
                    } catch {
                        throw error
                    }
                    for reason in failures {
                        if try !onEvaluationFailure(action, reason) {
                            throw _StopSuccessorTraversal()
                        }
                    }
                }
                try _visitActionCandidates(_visitAction)
            } catch is _StopSuccessorTraversal {
            }
            return found
        }
        public func enabledActions() throws -> [Action] {
            try _actions().filter { try isEnabled($0) }
        }
        public mutating func send(_ action: Action) throws -> Transition {
            let next = try SwiftTLA._singleNativeOutcome(
                _successors(for: action), missing: .noMatchingSuccessor, ambiguous: .ambiguousAction)
            let before = state
            _execution = next
            return Transition(action: action, before: before, after: state)
        }
        """)
        let directRoutes = model.api.actions.compactMap { api -> (name: String, id: Int, formalName: String)? in
            let action = program[api.compiledAction]
            guard api.bindings.isEmpty, action.bindings.isEmpty else { return nil }
            return (api.swiftIdentifier, action.id.ordinal,
                program.layout.actions[action.id.ordinal].renderedName)
        }
        try verifyGeneratedActionRoutingOutput(declarations, routes: directRoutes,
            allActions: model.api.actions.map { api in
                (name: api.swiftIdentifier, id: api.compiledAction.ordinal,
                    formalName: program.layout.actions[api.compiledAction.ordinal].renderedName,
                    publicBindings: api.bindings.filter(\.isPublic).count)
            },
            candidates: model.api.actions.map { api in
                (name: api.swiftIdentifier,
                    labels: api.bindings.filter(\.isPublic).map(\.swiftIdentifier))
            },
            configurationArguments: configurationArguments,
            boundRoutes: scalarBoundRoutes(program: program, actions: model.api.actions))
        return declarations
    }

    mutating func propertyDeclarations(configurationParameters: String) throws -> [DeclSyntax] {
        let arguments = machineArguments.isEmpty ? "" : ", " + machineArguments
        var declarations: [DeclSyntax] = []
        var checks: [String] = []
        let deadlock = try nativeDeclarations("public static var checksDeadlock: \(nativeBoolType) { \(program.behavior.checkDeadlock) }")
        try verifyGeneratedSourceDefaultDeadlock(deadlock.first,
            required: program.requiresSourceDefaultDeadlockOutput)
        declarations += deadlock
        declarations += try nativeDeclarations("public static var hasActionConstraint: \(nativeBoolType) { \(program.behavior.actionConstraint != nil) }")
        if let constraint = program.behavior.constraint {
            declarations += try nativeDeclarations("""
            private static func _constraintHolds(in state: Snapshot\(configurationParameters)) throws -> \(nativeBoolType) {
                \(try expression(constraint.expression))
            }
            public func satisfiesStateConstraint() throws -> \(nativeBoolType) {
                try Self._constraintHolds(in: _execution\(arguments))
            }
            """)
        } else {
            declarations += try nativeDeclarations("public func satisfiesStateConstraint() throws -> \(nativeBoolType) { true }")
        }
        if let actionConstraint = program.behavior.actionConstraint {
            let previousCheckingContextName = checkingContextName
            checkingContextName = "context"
            let body = try expression(actionConstraint.expression)
            checkingContextName = previousCheckingContextName
            declarations += try nativeDeclarations("""
            private static func _actionConstraintHolds(in state: Snapshot, nextState: Snapshot,
                checking context: inout CheckingContext<CheckingRegisters>?\(configurationParameters)) throws -> \(nativeBoolType) {
                \(body)
            }
            public func satisfiesActionConstraint(to successor: Self,
                checking context: inout CheckingContext<CheckingRegisters>) throws -> \(nativeBoolType) {
                var run: CheckingContext<CheckingRegisters>? = context
                defer { context = run! }
                return try Self._actionConstraintHolds(in: _execution, nextState: successor._execution,
                    checking: &run\(arguments))
            }
            """)
        } else {
            declarations += try nativeDeclarations("""
            public func satisfiesActionConstraint(to successor: Self,
                checking context: inout CheckingContext<CheckingRegisters>) throws -> \(nativeBoolType) { true }
            """)
        }
        for invariant in program.behavior.invariants {
            let previousCheckingLevelName = checkingLevelName
            checkingLevelName = "level"
            defer { checkingLevelName = previousCheckingLevelName }
            declarations += try nativeDeclarations("""
            private static func _invariant\(invariant.id.ordinal)(in state: Snapshot, atLevel level: \(nativeIntType)\(configurationParameters)) throws -> \(nativeBoolType) {
                \(try expression(invariant.predicate.expression))
            }
            """)
            checks.append("if checking.contains(.\(propertyCases[invariant.id]!)), try !Self._invariant\(invariant.id.ordinal)(in: _execution, atLevel: level\(arguments)) { result.append(.\(propertyCases[invariant.id]!)) }")
        }
        declarations += try nativeDeclarations("""
        public static var invariantProperties: [Property] { [\(program.behavior.invariants.map { ".\(propertyCases[$0.id]!)" }.joined(separator: ", "))] }
        public func violatedInvariants(checking: Set<Property> = Set(Property.allCases), atLevel level: \(nativeIntType)) throws -> [Property] {
            \(checks.isEmpty ? "return []" : "var result: [Property] = []\n" + checks.joined(separator: "\n") + "\nreturn result")
        }
        """)
        var reachabilityChecks: [String] = []
        for property in program.behavior.reachabilityProperties {
            declarations += try nativeDeclarations("""
            private static func _reachable\(property.id.ordinal)(in state: Snapshot\(configurationParameters)) throws -> \(nativeBoolType) {
                \(try expression(property.predicate.expression))
            }
            """)
            reachabilityChecks.append("if checking.contains(.\(propertyCases[property.id]!)), try Self._reachable\(property.id.ordinal)(in: _execution\(arguments)) { result.append(.\(propertyCases[property.id]!)) }")
        }
        declarations += try nativeDeclarations("""
        public static var reachabilityProperties: [Property] { [\(program.behavior.reachabilityProperties.map { ".\(propertyCases[$0.id]!)" }.joined(separator: ", "))] }
        public func matchedReachabilityProperties(checking: Set<Property> = Set(Property.allCases)) throws -> [Property] {
            \(reachabilityChecks.isEmpty ? "return []" : "var result: [Property] = []\n" + reachabilityChecks.joined(separator: "\n") + "\nreturn result")
        }
        """)
        var temporalProperties: [String] = []
        let captures = machineCaptures.joined(separator: ", ")
        let captureList = captures.isEmpty ? "" : "[\(captures)] "
        for property in program.behavior.temporalProperties {
            let boundNames = property.bindings.map { binder($0.binder) }
            let boundParameters = try property.bindings.map {
                ", \(binder($0.binder)): \(try swiftType(program.bindingTypes[$0.binder]!))"
            }.joined()
            let boundArguments = boundNames.map { ", \($0): \($0)" }.joined()
            let propertyCaptures = machineCaptures + boundNames
            let propertyCaptureList = propertyCaptures.isEmpty ? "" : "[\(propertyCaptures.joined(separator: ", "))] "
            var index = 0
            let predicates = try property.expression.map { query in
                let function = "_temporal\(property.id.ordinal)_\(index)"
                index += 1
                declarations += try nativeDeclarations("""
                private static func \(function)(in state: Snapshot, nextState: Snapshot\(configurationParameters)\(boundParameters)) throws -> \(nativeBoolType) {
                    \(try expression(query.expression))
                }
                """)
                return "{ \(propertyCaptureList)state, nextState in try Self.\(function)(in: state, nextState: nextState\(arguments)\(boundArguments)) }"
            }
            func condition(_ value: TemporalCondition<String>) -> String {
                switch value {
                case .always(let predicate): ".always(\(predicate))"
                case .eventually(let predicate): ".eventually(\(predicate))"
                case .alwaysEventually(let predicate): ".alwaysEventually(\(predicate))"
                case .eventuallyAlways(let predicate): ".eventuallyAlways(\(predicate))"
                case .leadsTo(let source, let target): ".leadsTo(\(source), \(target))"
                case .all(let conditions): ".all([\(conditions.map { condition($0) }.joined(separator: ", "))])"
                case .conditional(let predicate, let yes, let no):
                    ".conditional(\(predicate), then: \(condition(yes)), else: \(condition(no)))"
                }
            }
            if property.bindings.isEmpty {
                temporalProperties.append("if checking.contains(.\(propertyCases[property.id]!)) { result[.\(propertyCases[property.id]!)] = \(condition(predicates)) }")
            } else {
                let name = "_temporalMembers\(property.id.ordinal)"
                let loops = try property.bindings.map { binding in
                    "for \(binder(binding.binder)) in \(try actionDomain(binding, state: "")) {"
                }.joined(separator: "\n")
                temporalProperties.append("""
                if checking.contains(.\(propertyCases[property.id]!)) {
                var \(name): [TemporalCondition<@Sendable (Snapshot, Snapshot) throws -> \(nativeBoolType)>] = []
                \(loops)
                \(name).append(\(condition(predicates)))
                \(String(repeating: "}\n", count: property.bindings.count))
                result[.\(propertyCases[property.id]!)] = .all(\(name))
                }
                """)
            }
        }
        let unsupportedRefinements = program.refinements.filter { !supportsNativeRefinement($0) }.map {
            "if checking.contains(.\(propertyCases[$0.id]!)) { throw ExplorationError.unsupportedRefinement(\(String(reflecting: $0.name))) }"
        }.joined(separator: "\n")
        let propertyBody = unsupportedRefinements + "\n" + (temporalProperties.isEmpty ? "return [:]" :
            "var result: [Property: TemporalCondition<@Sendable (Snapshot, Snapshot) throws -> \(nativeBoolType)>] = [:]\n" + temporalProperties.joined(separator: "\n") + "\nreturn result")
        declarations += try nativeDeclarations("""
        public func temporalProperties(checking: Set<Property> = Set(Property.allCases)) throws -> [Property: TemporalCondition<@Sendable (Snapshot, Snapshot) throws -> \(nativeBoolType)>] {
            \(propertyBody)
        }
        """)
        declarations += try fairnessDeclarations(program.behavior.fairness,
            methodName: "fairnessConditions", suffix: "Default",
            configurationParameters: configurationParameters, arguments: arguments,
            captureList: captureList)
        for (index, profile) in program.behavior.fairnessProfiles.enumerated() {
            declarations += try fairnessDeclarations(profile.fairness,
                methodName: "_fairnessProfile\(index)Conditions", suffix: "Profile\(index)",
                configurationParameters: configurationParameters, arguments: arguments,
                captureList: captureList)
        }
        if let assume = program.behavior.assume {
            declarations += try nativeDeclarations("""
            private static func _assumptionsHold(in state: Snapshot\(configurationParameters)) throws -> \(nativeBoolType) {
                \(try expression(assume.expression))
            }
            public func assumptionsHold() throws -> \(nativeBoolType) {
                try Self._assumptionsHold(in: _execution\(arguments))
            }
            """)
        } else {
            declarations += try nativeDeclarations("public func assumptionsHold() throws -> \(nativeBoolType) { true }")
        }
        return declarations
    }

    private mutating func fairnessDeclarations(
        _ conditions: [CompiledFairnessCondition], methodName: String, suffix: String,
        configurationParameters: String, arguments: String, captureList: String
    ) throws -> [DeclSyntax] {
        var declarations: [DeclSyntax] = []
        var fairness: [String] = []
        var configuredFairness: [String] = []
        for (index, condition) in conditions.enumerated() {
            let name: String
            let matcher: String
            let changes: String
            if let projection = condition.projection {
                let function = "_fairnessChanges\(suffix)_\(index)"
                declarations += try nativeDeclarations("""
                private static func \(function)(in state: Snapshot, nextState: Snapshot\(configurationParameters)) throws -> \(nativeBoolType) {
                    \(try expression(projection)) != \(try expression(projection, state: "nextState."))
                }
                """)
                changes = "{ \(captureList)state, nextState in try Self.\(function)(in: state, nextState: nextState\(arguments)) }"
            } else {
                changes = "nil"
            }
            switch condition.scope {
            case .next:
                name = "Next"
                matcher = "{ _ in true }"
            case .action(let id):
                let action = model.api.actions.first { $0.compiledAction == id }!
                name = program.layout.actions[id.ordinal].renderedName
                matcher = "{ action in if case .\(action.swiftIdentifier) = action { return true }; return false }"
            case .actionGroup(let ids):
                name = ids.map { program.layout.actions[$0.ordinal].renderedName }.joined(separator: " or ")
                let cases = ids.map { id -> String in
                    let action = model.api.actions.first { $0.compiledAction == id }!
                    return "if case .\(action.swiftIdentifier) = action { return true }"
                }.joined(separator: "; ")
                matcher = "{ action in \(cases); return false }"
            case .actionCall(let call):
                let action = model.api.actions.first { $0.compiledAction == call.action }!
                let bindings = program[call.action].bindings
                let arguments = try zip(bindings.indices, call.arguments).compactMap { index, value -> String? in
                    guard action.bindings[index].isPublic else { return nil }
                    return "\(action.bindings[index].swiftIdentifier): \(try literal(value, as: program.bindingTypes[bindings[index].binder]!))"
                }
                let value = ".\(action.swiftIdentifier)" + (arguments.isEmpty ? "" : "(\(arguments.joined(separator: ", ")))")
                name = FormalActionCall(
                    name: program.layout.actions[call.action.ordinal].renderedName,
                    arguments: try call.arguments.map { try $0.rendered(using: program.layout) }
                ).description
                matcher = "{ \(captureList)action in action == \(value) }"
            case .actionCallGroup:
                throw unsupported("unexpanded process fairness group")
            case .eachAction(let id):
                let action = model.api.actions.first { $0.compiledAction == id }!
                let bindings = program[id].bindings
                var loops: [String] = []
                var arguments: [String] = []
                for (index, binding) in bindings.enumerated() {
                    try program.requireImmutableDomain(binding.domain, path: "fairness.\(id.ordinal).domain")
                    loops.append("for \(binder(binding.binder)) in \(try actionDomain(binding, state: "")) {")
                    if action.bindings[index].isPublic {
                        arguments.append("\(action.bindings[index].swiftIdentifier): \(binder(binding.binder))")
                    }
                }
                let value = ".\(action.swiftIdentifier)" + (arguments.isEmpty ? "" : "(\(arguments.joined(separator: ", ")))")
                configuredFairness.append(loops.joined(separator: "\n") + "\n" + """
                let _action: Action = \(value)
                _fairness.append((name: try formalCall(for: _action).description,
                    isStrong: \(condition.isStrong), matches: { [ _action ] in $0 == _action }, changes: \(changes)))
                """ + String(repeating: "\n}", count: loops.count))
                continue
            case .eachActionGroup(let ids):
                guard let first = ids.first else { throw unsupported("empty process fairness group") }
                let bindings = program[first].bindings
                var loops: [String] = []
                for binding in bindings {
                    try program.requireImmutableDomain(binding.domain, path: "fairness.\(first.ordinal).domain")
                    loops.append("for \(binder(binding.binder)) in \(try actionDomain(binding, state: "")) {")
                }
                let values = ids.map { id -> String in
                    let action = model.api.actions.first { $0.compiledAction == id }!
                    let arguments = zip(action.bindings, bindings).compactMap { binding, value -> String? in
                        binding.isPublic ? "\(binding.swiftIdentifier): \(binder(value.binder))" : nil
                    }
                    return ".\(action.swiftIdentifier)" + (arguments.isEmpty ? "" : "(\(arguments.joined(separator: ", ")))")
                }
                configuredFairness.append(loops.joined(separator: "\n") + "\n" + """
                \(bindings.map { "_ = \(binder($0.binder))" }.joined(separator: "\n"))
                let _actions: [Action] = [\(values.joined(separator: ", "))]
                _fairness.append((name: try _actions.map { try formalCall(for: $0).description }.joined(separator: " or "),
                    isStrong: \(condition.isStrong), matches: { [ _actions ] in _actions.contains($0) }, changes: \(changes)))
                """ + String(repeating: "\n}", count: loops.count))
                continue
            }
            fairness.append("(name: \(String(reflecting: name + (condition.projection == nil ? "" : " [projection \(index)]"))), isStrong: \(condition.isStrong), matches: \(matcher), changes: \(changes))")
        }
        declarations += try nativeDeclarations("""
        \(methodName == "fairnessConditions" ? "public" : "fileprivate") func \(methodName)() throws -> [MachineFairnessCondition<Snapshot, Action>] {
            \(configuredFairness.isEmpty ? "let" : "var") _fairness: [(name: \(nativeStringType), isStrong: \(nativeBoolType), matches: @Sendable (Action) -> \(nativeBoolType), changes: (@Sendable (Snapshot, Snapshot) throws -> \(nativeBoolType))?)] = [\(fairness.joined(separator: ",\n"))]
            \(configuredFairness.joined(separator: "\n"))
            return _fairness.sorted { $0.name < $1.name }
        }
        """)
        return declarations
    }

}

func verifyRandomSubsetInitialSupport(_ declaration: DeclSyntax?, expected: [(String, Bool)]) throws {
    let tokens = declaration.map { Array($0.tokens(viewMode: .sourceAccurate)).map(\.text) } ?? []
    func occurrences(_ source: String) -> Int {
        let pattern = Array(Parser.parse(source: source).tokens(viewMode: .sourceAccurate))
            .map(\.text).filter { !$0.isEmpty }
        guard !pattern.isEmpty, tokens.count >= pattern.count else { return 0 }
        return (0...(tokens.count - pattern.count)).filter {
            tokens[$0..<($0 + pattern.count)].elementsEqual(pattern)
        }.count
    }
    for (name, functionDomain) in expected {
        let sample = functionDomain ? "randomFunctionSubset" : "randomSubset"
        let exhaustive = functionDomain ? "randomFunctionInitialSupport" : "randomSubsetInitialSupport"
        let required = [
            "try SwiftTLA._NativeMachineOperations.validateRandomSubsetCount(\(name)_sampleLimit)",
            "try SwiftTLA._NativeMachineOperations.\(sample)(upTo: \(name)_sampleLimit",
            "try SwiftTLA._NativeMachineOperations.\(exhaustive)(upTo: \(name)_sampleLimit",
        ]
        guard required.allSatisfy({ occurrences($0) == 1 }) else {
            throw CompilationDiagnostic(
                code: .unsupportedGeneratedValueShape, stage: .validation,
                path: "native._initialStates.randomSubset.\(name)",
                expected: "one count validation, sampled draw, and exhaustive support call",
                actual: "the emitted initialization does not contain the required operations exactly once",
                nextSafeAction: "Report this native code generation failure.")
        }
    }
}

func verifyGeneratedInitialConstruction(_ declarations: [DeclSyntax], configured: Bool,
                                        sampled: Bool = false) throws {
    let parameters = configured ? "configuration: Configuration" : ""
    let appendedParameters = configured ? ", configuration: Configuration" : ""
    let appendedArguments = configured ? ", configuration: configuration" : ""
    let samplingParameter = sampled ? ", _sampleRandomSubset: \(nativeBoolType) = false" : ""
    let unselectedArguments = "_selectedInitial: nil as State?\(sampled ? ", _sampleRandomSubset: false" : "")\(appendedArguments)"
    let expected = Parser.parse(source: """
    private static func _completedInitialStates(_selectedInitial: State? = nil\(samplingParameter)\(appendedParameters)) throws -> [Snapshot] {
        let outcome: SwiftTLA.InitialEvaluationOutcomes<Snapshot> = try Self._initialStates(_selectedInitial: _selectedInitial\(sampled ? ", _sampleRandomSubset: _sampleRandomSubset" : "")\(appendedArguments))
        return try SwiftTLA._completeNativeInitialOutcomes(outcome)
    }
    public static func initialOutcomes(\(parameters)) throws -> SwiftTLA.InitialEvaluationOutcomes<Self> {
        let outcome: SwiftTLA.InitialEvaluationOutcomes<Snapshot> = try Self._initialStates(\(unselectedArguments))
        return SwiftTLA._mapNativeInitialOutcomes(outcome) { Self(execution: $0\(appendedArguments)) }
    }
    public static func initialMachines(\(parameters)) throws -> [Self] {
        SwiftTLA._mapNativeOutcomes(try Self._completedInitialStates(\(unselectedArguments)) as [Snapshot]) { Self(execution: $0\(appendedArguments)) }
    }
    public static func makeMachine(\(parameters)) throws -> Self {
        let execution = try SwiftTLA._singleNativeOutcome(
            Self._completedInitialStates(\(unselectedArguments)) as [Snapshot], missing: .noInitialState, ambiguous: .ambiguousInitialState)
        return Self(execution: execution\(appendedArguments))
    }
    public static func makeMachine(_ initial: State\(appendedParameters)) throws -> Self {
        let execution = try SwiftTLA._singleNativeOutcome(
            Self._completedInitialStates(_selectedInitial: initial as State?\(sampled ? ", _sampleRandomSubset: false" : "")\(appendedArguments)) as [Snapshot], missing: .invalidInitialState, ambiguous: .ambiguousInitialState)
        return Self(execution: execution\(appendedArguments))
    }
    \(sampled ? """
    public static func sampledInitialMachines(\(parameters)) throws -> [Self] {
        SwiftTLA._mapNativeOutcomes(try Self._completedInitialStates(_selectedInitial: nil as State?, _sampleRandomSubset: true\(appendedArguments)) as [Snapshot]) { Self(execution: $0\(appendedArguments)) }
    }
    """ : "")
    """).statements.compactMap { $0.item.as(DeclSyntax.self) }
    let actual = Array(declarations.dropFirst().prefix(expected.count))
    let actualTokens = actual.map { Array($0.tokens(viewMode: .sourceAccurate)).map(\.text) }
    let expectedTokens = expected.map { Array($0.tokens(viewMode: .sourceAccurate)).map(\.text) }
    let matches = declarations.first?.as(FunctionDeclSyntax.self)?.name.text == "_initialStates"
        && expected.count == (sampled ? 6 : 5) && actual.count == expected.count
        && actualTokens == expectedTokens
    guard matches else {
        let mismatch = zip(actualTokens, expectedTokens).enumerated().first { $0.element.0 != $0.element.1 }
        let difference = mismatch.map {
            "method \($0.offset): actual \($0.element.0.prefix(40)), expected \($0.element.1.prefix(40))"
        } ?? "declaration counts: actual \(declarations.count), expected 4"
        throw CompilationDiagnostic(
            code: .unsupportedGeneratedValueShape, stage: .validation,
            path: "native.initialConstruction",
            expected: "the checked initialMachines and both makeMachine construction rules",
            actual: difference,
            nextSafeAction: "Report this native code generation failure."
        )
    }
}

private func checkedIntInitialDomainValue(_ root: CompiledExpression,
                                          slots: [VariableID: String]) -> String? {
    var pending = [(root, false)]
    var values: [String] = []
    while let (node, expanded) = pending.popLast() {
        if node.resultType == .int {
            guard let value = checkedIntInitialValue(node, slots: slots) else { return nil }
            values.append(value)
            continue
        }
        let types: [CompiledValueType]
        switch (node.operation, node.resultType) {
        case (.integerSet, .set(.int)) where node.children.isEmpty: types = []
        case (.equal, .bool) where node.children.count == 2: types = [.int, .int]
        case (.integerRange, .set(.int)) where node.children.count == 2: types = [.int, .int]
        case (.setLiteral, .set(.int)): types = node.children.map { _ in .int }
        case (.ifThenElse, .set(.int)) where node.children.count == 3:
            types = [.bool, .set(.int), .set(.int)]
        default: return nil
        }
        guard zip(node.children, types).allSatisfy({ $0.0.resultType == $0.1 }) else { return nil }
        if !expanded {
            pending.append((node, true))
            pending.append(contentsOf: node.children.reversed().map { ($0, false) })
            continue
        }
        guard values.count >= types.count else { return nil }
        let children = Array(values.suffix(types.count))
        values.removeLast(types.count)
        let value: String
        switch node.operation {
        case .integerSet: value = "(try SwiftTLA._NativeMachineOperations.integerSet())"
        case .equal: value = "(\(children[0]) == \(children[1]))"
        case .integerRange:
            value = "(try SwiftTLA._NativeMachineOperations.integerRange(\(children[0]), \(children[1])))"
        case .setLiteral: value = "Set<\(nativeIntType)>([\(children.joined(separator: ", "))])"
        case .ifThenElse: value = "(\(children[0]) ? \(children[1]) : \(children[2]))"
        default: return nil
        }
        values.append(value)
    }
    return values.count == 1 ? values[0] : nil
}

private func checkedIntInitialDomainMembership(_ root: CompiledExpression, candidate: String,
                                               slots: [VariableID: String], predicateNames: [String],
                                               nextPredicate: inout Int) -> String? {
    var nodes = [root]
    var symbolic = false
    while let node = nodes.popLast() {
        if node.operation == .integerRange || node.operation == .integerSet { symbolic = true; break }
        nodes.append(contentsOf: node.children)
    }
    if !symbolic {
        return checkedIntInitialDomainValue(root, slots: slots).map { "(\($0).contains(\(candidate)))" }
    }
    var pending: [(CompiledExpression, String?)] = [(root, nil)]
    var values: [(declaration: String, call: String)] = []
    while let (node, assignedName) = pending.popLast() {
        guard let name = assignedName else {
            guard nextPredicate < predicateNames.count else { return nil }
            let name = predicateNames[nextPredicate]
            nextPredicate += 1
            pending.append((node, name))
            if case .ifThenElse = node.operation {
                guard node.children.count == 3 else { return nil }
                pending.append((node.children[2], nil))
                pending.append((node.children[1], nil))
            }
            continue
        }
        let body: String
        switch node.operation {
        case .integerSet:
            guard node.children.isEmpty, node.resultType == .set(.int) else { return nil }
            body = "return { _ in true }"
        case .integerRange:
            guard node.children.count == 2,
                  let lower = checkedIntInitialDomainValue(node.children[0], slots: slots),
                  let upper = checkedIntInitialDomainValue(node.children[1], slots: slots) else { return nil }
            body = """
            let bounds = (\(lower), \(upper))
            return { candidate in bounds.0 <= candidate && candidate <= bounds.1 }
            """
        case .setLiteral:
            guard let members = checkedIntInitialDomainValue(node, slots: slots) else { return nil }
            body = "let members = \(members)\nreturn { members.contains($0) }"
        case .ifThenElse:
            guard node.children.count == 3, values.count >= 2,
                  let condition = checkedIntInitialDomainValue(node.children[0], slots: slots) else { return nil }
            let second = values.removeLast()
            let first = values.removeLast()
            body = """
            \(first.declaration)
            \(second.declaration)
            if \(condition) { return \(first.call) }
            return \(second.call)
            """
        default: return nil
        }
        values.append(("func \(name)() throws -> ((\(nativeIntType)) -> \(nativeBoolType)) {\n\(body)\n}", "try \(name)()"))
    }
    guard values.count == 1, let predicate = values.first else { return nil }
    return """
    (try { () throws -> \(nativeBoolType) in
        \(predicate.declaration)
        let contains = \(predicate.call)
        let candidate = \(candidate)
        return contains(candidate)
    }())
    """
}

private func checkedIntInitialValue(_ root: CompiledExpression,
                                    slots: [VariableID: String]) -> String? {
    let arithmetic: Bool
    if case .add = root.operation { arithmetic = true } else { arithmetic = false }
    var pending = [(root, false)]
    var values: [String] = []
    var statements: [String] = []
    while let (node, expanded) = pending.popLast() {
        guard node.resultType == .int else { return nil }
        let value: String
        switch node.operation {
        case .add:
            guard node.children.count == 2 else { return nil }
            if !expanded {
                pending.append((node, true))
                pending.append((node.children[1], false))
                pending.append((node.children[0], false))
                continue
            }
            guard values.count >= 2 else { return nil }
            let rhs = values.removeLast()
            let lhs = values.removeLast()
            value = "try SwiftTLA._nativeIntAdd(\(lhs), \(rhs))"
        case .stateVariable(let id):
            guard node.children.isEmpty, let slot = slots[id] else { return nil }
            value = slot
        case .value(.integer(let integer)):
            guard node.children.isEmpty else { return nil }
            value = integer == Int.min ? "\(nativeIntType).min" : String(integer)
        default: return nil
        }
        if arithmetic {
            let name = "_arithmetic\(statements.count)"
            statements.append("let \(name): \(nativeIntType) = \(value)")
            values.append(name)
        } else {
            values.append(value)
        }
    }
    guard values.count == 1, let value = values.first else { return nil }
    if !arithmetic { return value }
    return "(try { () throws -> \(nativeIntType) in\n\(statements.joined(separator: "\n"))\nreturn \(value)\n}())"
}

func verifyOrderedIntInitialExpression(_ declaration: DeclSyntax?, named name: String,
                                       expression: CompiledExpression,
                                       slots: [VariableID: String]) throws {
    enum Step: Equatable {
        case integer(Int)
        case slot(String)
        case add(Int, Int)
    }
    func invalid() -> CompilationDiagnostic {
        CompilationDiagnostic(code: .unsupportedGeneratedValueShape, stage: .validation,
            path: "native._initialStates.expression.\(name)",
            expected: "the compiled Int expression's ordered reads and checked additions",
            actual: "the generated Swift initializer has another value or evaluation order",
            nextSafeAction: "Report this native initialization generation failure.")
    }
    var expected: [Step] = []
    var values: [Int] = []
    var pending = [(expression, false)]
    while let (node, expanded) = pending.popLast() {
        guard node.resultType == .int else { throw invalid() }
        let step: Step
        switch node.operation {
        case .add:
            guard node.children.count == 2 else { throw invalid() }
            if !expanded {
                pending.append((node, true))
                pending.append((node.children[1], false))
                pending.append((node.children[0], false))
                continue
            }
            guard values.count >= 2 else { throw invalid() }
            let right = values.removeLast()
            step = .add(values.removeLast(), right)
        case .stateVariable(let id):
            guard node.children.isEmpty, let slot = slots[id] else { throw invalid() }
            step = .slot(slot)
        case .value(.integer(let integer)):
            guard node.children.isEmpty else { throw invalid() }
            step = .integer(integer)
        default: throw invalid()
        }
        values.append(expected.count)
        expected.append(step)
    }
    guard values == [expected.count - 1] else { throw invalid() }
    let tokens = declaration.map { Array($0.tokens(viewMode: .sourceAccurate)).map(\.text) } ?? []
    let binding = ["let", name, ":"] + nativeIntTypeTokens + ["="]
    let starts = tokens.indices.filter { index in
        index + binding.count <= tokens.count &&
            Array(tokens[index..<(index + binding.count)]) == binding
    }
    guard starts.count == 1, let start = starts.first else { throw invalid() }
    var cursor = start + binding.count
    func take(_ pattern: [String]) -> Bool {
        guard cursor + pattern.count <= tokens.count,
              Array(tokens[cursor..<(cursor + pattern.count)]) == pattern else { return false }
        cursor += pattern.count
        return true
    }
    func arithmeticIndex() -> Int? {
        guard cursor < tokens.count, tokens[cursor].hasPrefix("_arithmetic"),
              let index = Int(tokens[cursor].dropFirst("_arithmetic".count)) else { return nil }
        cursor += 1
        return index
    }
    func readStep(available: Int) -> Step? {
        if take(["try", "SwiftTLA", ".", "_nativeIntAdd", "("]) {
            guard let left = arithmeticIndex(), take([","]), let right = arithmeticIndex(),
                  take([")"]), left < available, right < available else { return nil }
            return .add(left, right)
        }
        guard cursor < tokens.count else { return nil }
        if take(nativeIntTypeTokens + [".", "min"]) { return .integer(Int.min) }
        let negative = take(["-"])
        if cursor < tokens.count, let integer = Int((negative ? "-" : "") + tokens[cursor]) {
            cursor += 1
            return .integer(integer)
        }
        if !negative, cursor < tokens.count, slots.values.contains(tokens[cursor]) {
            let slot = tokens[cursor]
            cursor += 1
            return .slot(slot)
        }
        return nil
    }
    if case .add = expression.operation {
        guard take(["(", "try", "{", "(", ")", "throws", "->"] + nativeIntTypeTokens + ["in"]) else { throw invalid() }
        for (index, step) in expected.enumerated() {
            guard take(["let", "_arithmetic\(index)", ":"] + nativeIntTypeTokens + ["="]),
                  readStep(available: index) == step else { throw invalid() }
        }
        guard take(["return", "_arithmetic\(expected.count - 1)", "}", "(", ")", ")"]) else {
            throw invalid()
        }
    } else {
        guard expected.count == 1, readStep(available: 0) == expected[0] else { throw invalid() }
    }
    guard cursor < tokens.count, ["if", "let", "result", "}", "evaluatingInitializerOrdinal"].contains(tokens[cursor]) else {
        throw invalid()
    }
}

func verifyGeneratedInitialBindings(
    _ declaration: DeclSyntax?, expected: [String], expectedLoops: [String: String],
    expectedCandidateSources: [String: String], expectedIntLiterals: [String: Int] = [:],
    expectedControlLocations: [String: Int] = [:],
    expectedIntExpressions: [String: CompiledExpression] = [:],
    stateSlots: [VariableID: String] = [:]
) throws {
    guard let initialStates = declaration?.as(FunctionDeclSyntax.self) else {
        throw CompilationDiagnostic(code: .unsupportedGeneratedValueShape, stage: .validation,
            path: "native._initialStates.bindings", expected: expected.joined(separator: ", "),
            actual: "missing _initialStates function",
            nextSafeAction: "Report this native code generation failure.")
    }
    let expectedBindings = Set(expected)
    let tokens = Array(initialStates.tokens(viewMode: .sourceAccurate)).map(\.text)
    var actual: [String] = []
    for index in 0..<max(0, tokens.count - 1) where tokens[index] == "let" || tokens[index] == "for" {
        let binding = "\(tokens[index]) \(tokens[index + 1])"
        if expectedBindings.contains(binding) {
            actual.append(binding)
        }
    }
    guard actual == expected else {
        throw CompilationDiagnostic(code: .unsupportedGeneratedValueShape, stage: .validation,
            path: "native._initialStates.bindings", expected: expected.joined(separator: ", "),
            actual: "\(actual.joined(separator: ", ")) (source tokens: \(tokens.prefix(80).joined(separator: " ")))",
            nextSafeAction: "Report this native code generation failure.")
    }
    func expectedTokens(_ source: String) -> [String] {
        Array(Parser.parse(source: source).tokens(viewMode: .sourceAccurate)).map(\.text).filter { !$0.isEmpty }
    }
    func verifyInitializer(_ name: String, type: String, value: String) throws {
        let required = ["let", name, ":"] + expectedTokens(type) + ["="] + expectedTokens(value)
        let positions = tokens.indices.filter { index in
            index + 1 < tokens.count && tokens[index] == "let" && tokens[index + 1] == name
        }
        guard positions.count == 1, let start = positions.first,
              start + required.count < tokens.count,
              Array(tokens[start..<(start + required.count)]) == required,
              ["if", "let", "for", "result", "}", "evaluatingInitializerOrdinal"].contains(tokens[start + required.count]) else {
            throw CompilationDiagnostic(code: .unsupportedGeneratedValueShape, stage: .validation,
                path: "native._initialStates.value.\(name)",
                expected: "the compiled \(type) initializer \(value)",
                actual: "the emitted initializer differs from its compiled value",
                nextSafeAction: "Report this native initialization generation failure.")
        }
    }
    for (name, value) in expectedIntLiterals {
        try verifyInitializer(name, type: nativeIntType, value: value == Int.min ? "\(nativeIntType).min" : String(value))
    }
    for (name, expression) in expectedIntExpressions {
        guard let expected = checkedIntInitialValue(expression, slots: stateSlots) else {
            throw CompilationDiagnostic(code: .unsupportedGeneratedValueShape, stage: .validation,
                path: "native._initialStates.expression.\(name)",
                expected: "a checked Int literal, prior-state read, or addition",
                actual: "the compiled initializer has another expression form",
                nextSafeAction: "Report this native initialization checking failure.")
        }
        try verifyInitializer(name, type: nativeIntType, value: expected)
    }
    for (name, id) in expectedControlLocations {
        try verifyInitializer(name, type: "_ControlLocation", value: "_ControlLocation.location\(id)")
    }
    for (name, sequence) in expectedLoops {
        var positions: [Int] = []
        if tokens.count >= 3 {
            for index in 0..<(tokens.count - 2) {
                if tokens[index] == "for", tokens[index + 1] == name, tokens[index + 2] == "in" {
                    positions.append(index)
                }
            }
        }
        let domain = expectedTokens(sequence)
        let start = (positions.first ?? 0) + 3
        let end = start + domain.count
        guard positions.count == 1, end < tokens.count,
              Array(tokens[start..<end]) == domain, tokens[end] == "{" else {
            throw CompilationDiagnostic(code: .unsupportedGeneratedValueShape, stage: .validation,
                path: "native._initialStates.domains.\(name)", expected: sequence,
                actual: "\(tokens.dropFirst(start).prefix(domain.count + 1))",
                nextSafeAction: "Report this native code generation failure.")
        }
    }
    for (name, source) in expectedCandidateSources {
        let expectedCall = "\(name): ["
        let expectedEnumeration = "enumerate: { \(source) }"
        let hasCandidateBinding = initialStates.description.contains(expectedCall)
        let hasExpectedEnumeration = initialStates.description.contains(expectedEnumeration)
        guard hasCandidateBinding, hasExpectedEnumeration else {
            throw CompilationDiagnostic(code: .unsupportedGeneratedValueShape, stage: .validation,
                path: "native._initialStates.candidates.\(name)", expected: source,
                actual: "candidate binding=\(hasCandidateBinding), exact enumeration=\(hasExpectedEnumeration)",
                nextSafeAction: "Report this native code generation failure.")
        }
    }
}

func verifyGeneratedSnapshotOutput(
    _ declaration: DeclSyntax?, hiddenFields: [(name: String, type: String)],
    structuralIdentity: Bool = false
) throws {
    var checked = declaration
    if structuralIdentity, var snapshot = declaration?.as(StructDeclSyntax.self) {
        let methods = snapshot.memberBlock.members.compactMap { $0.decl.as(FunctionDeclSyntax.self) }
        let expectedMethods = Parser.parse(source: """
        public static func == (lhs: Self, rhs: Self) -> \(nativeBoolType) {}
        public func hash(into hasher: inout SwiftTLA._NativeMachineOperations.StateHasher) {}
        """).statements.compactMap { $0.item.as(FunctionDeclSyntax.self) }
        let headers = (methods + expectedMethods).map { method -> [String] in
            var signature = method
            signature.body = nil
            return signature.tokens(viewMode: .sourceAccurate).map(\.text)
        }
        if methods.count == 2, expectedMethods.count == 2, methods.allSatisfy({ !$0.hasError }),
           Array(headers.prefix(2)) == Array(headers.suffix(2)) {
            snapshot.memberBlock.members = snapshot.memberBlock.members.filter {
                !$0.decl.is(FunctionDeclSyntax.self)
            }
            checked = DeclSyntax(snapshot)
        } else {
            checked = nil
        }
    }
    let fields = hiddenFields.map { "let \($0.name): \($0.type)" }.joined(separator: "\n")
    let expected = Parser.parse(source: """
    public struct Snapshot: Hashable, Sendable {
        public let state: State
        \(fields)
    }
    """).statements.first?.item.as(StructDeclSyntax.self)
    let actualTokens = checked.map { Array($0.tokens(viewMode: .sourceAccurate)).map(\.text) }
    let expectedTokens = expected.map { Array($0.tokens(viewMode: .sourceAccurate)).map(\.text) }
    guard actualTokens == expectedTokens else {
        throw CompilationDiagnostic(
            code: .unsupportedGeneratedValueShape, stage: .validation,
            path: "native.Snapshot",
            expected: "the public state and every hidden field, plus typed structural identity when required",
            actual: "the generated snapshot declaration differs from the checked rule",
            nextSafeAction: "Report this native code generation failure."
        )
    }
}

func verifyGeneratedStateConstructorOutput(
    _ declaration: DeclSyntax?, fields: [(name: String, type: String, ordinal: Int, formalName: String)]
) throws {
    let state = declaration?.as(StructDeclSyntax.self)
    let variables = state?.memberBlock.members.compactMap { $0.decl.as(VariableDeclSyntax.self) } ?? []
    let initializers = state?.memberBlock.members.compactMap { $0.decl.as(InitializerDeclSyntax.self) } ?? []
    let expectedFields = fields.compactMap { field in
        Parser.parse(source: "public let \(field.name): \(field.type)")
            .statements.first?.item.as(VariableDeclSyntax.self)
    }
    let parameters = fields.map { "\($0.name) _value\($0.ordinal): \($0.type)" }.joined(separator: ", ")
    let assignments = fields.map { "self.\($0.name) = _value\($0.ordinal)" }.joined(separator: "\n")
    let expectedInitializer = Parser.parse(source: """
    public init(\(parameters)) {
        \(assignments)
    }
    """).statements.first?.item.as(InitializerDeclSyntax.self)
    let identityEntries = fields.map {
        "\\State.\($0.name): .init(swiftName: \(String(reflecting: $0.name)), formalName: \(String(reflecting: $0.formalName)))"
    }.joined(separator: ",\n")
    let expectedIdentities = Parser.parse(source: """
    public static var fieldIdentities: [PartialKeyPath<State>: GeneratedModelFieldIdentity] {
        [\(identityEntries.isEmpty ? ":" : identityEntries)]
    }
    """).statements.first?.item.as(VariableDeclSyntax.self)
    let identities = variables.filter {
        $0.bindings.first?.pattern.as(IdentifierPatternSyntax.self)?.identifier.text == "fieldIdentities"
    }
    let fieldsMatch = expectedFields.count == fields.count && variables.count == fields.count + 2
        && zip(variables, expectedFields).allSatisfy { pair in
            Array(pair.0.tokens(viewMode: .sourceAccurate)).map(\.text)
                == Array(pair.1.tokens(viewMode: .sourceAccurate)).map(\.text)
        }
    guard state?.name.text == "State", fieldsMatch, initializers.count == 1,
          identities.count == 1, let expectedIdentities,
          Array(identities[0].tokens(viewMode: .sourceAccurate)).map(\.text)
            == Array(expectedIdentities.tokens(viewMode: .sourceAccurate)).map(\.text),
          let expectedInitializer,
          Array(initializers[0].tokens(viewMode: .sourceAccurate)).map(\.text)
            == Array(expectedInitializer.tokens(viewMode: .sourceAccurate)).map(\.text) else {
        throw CompilationDiagnostic(
            code: .unsupportedGeneratedValueShape, stage: .validation,
            path: "native.State.init",
            expected: "one field, matching constructor assignment, and formal identity per public state variable",
            actual: "the generated state declaration differs from the checked rule",
            nextSafeAction: "Report this native code generation failure."
        )
    }
}

func verifyGeneratedUpdateMergeOutput(
    _ declaration: DeclSyntax?, slots: [String], recordTypes: [String: String] = [:]
) throws {
    let merge = declaration?.as(StructDeclSyntax.self)?.memberBlock.members.compactMap {
        $0.decl.as(FunctionDeclSyntax.self)
    }.first { $0.name.text == "merging" }
    var actual = merge.map { Array($0.tokens(viewMode: .sourceAccurate)) } ?? []
    var ordersMatch = Set(recordTypes.keys).isSubset(of: Set(slots))
    var orderFailure = ""
    for slot in slots where recordTypes[slot] != nil {
        let type = recordTypes[slot]!
        let prefix = Parser.parse(source:
            "let _mergeEqual_\(slot) = { (lhs: \(type), rhs: \(type)) -> \(nativeBoolType) in")
            .tokens(viewMode: .sourceAccurate).map(\.text).filter { !$0.isEmpty }
        let positions = actual.indices.filter { index in
            index + prefix.count <= actual.count
                && actual[index..<(index + prefix.count)].map(\.text).elementsEqual(prefix)
        }
        guard positions.count == 1, let start = positions.first else {
            ordersMatch = false
            orderFailure = "slot=\(slot), prefixes=\(positions.count), expected=\(prefix.prefix(30))"
            break
        }
        let body = start + prefix.count
        var cursor = body
        var depth = 1
        while cursor < actual.count, depth > 0 {
            if actual[cursor].tokenKind == .leftBrace { depth += 1 }
            if actual[cursor].tokenKind == .rightBrace { depth -= 1 }
            cursor += 1
        }
        guard depth == 0 else { ordersMatch = false; break }
        // Comparator interpretation remains separate from the exact surrounding merge rule.
        actual.removeSubrange(body..<(cursor - 1))
    }
    var expected = ["func", "merging", "(", "_", "other", ":", "Self", ")", "->", "Self", "?", "{",
                    "var", "result", "=", "self"]
    for slot in slots {
        if let type = recordTypes[slot] {
            let source = """
            guard SwiftTLA._NativeMachineOperations.mergeUpdate(&result.\(slot), other.\(slot), equivalent: { lhs, rhs in
                let _mergeEqual_\(slot) = { (lhs: \(type), rhs: \(type)) -> \(nativeBoolType) in }
                return _mergeEqual_\(slot)(lhs, rhs)
            }) else { return nil }
            """
            expected += Parser.parse(source: source).tokens(viewMode: .sourceAccurate)
                .map(\.text).filter { !$0.isEmpty }
        } else {
            expected += ["guard", "SwiftTLA", ".", "_NativeMachineOperations", ".", "mergeUpdate", "(", "&", "result", ".",
                         slot, ",", "other", ".", slot, ")", "else", "{", "return", "nil", "}"]
        }
    }
    expected += ["return", "result", "}"]
    let actualText = actual.map(\.text)
    guard let merge, !merge.hasError, ordersMatch, actualText == expected else {
        let mismatch = zip(actualText, expected).enumerated().first { $0.element.0 != $0.element.1 }?.offset ?? min(actualText.count, expected.count)
        let scope = merge?.detached
        let missing = scope?.tokens(viewMode: .all).filter { $0.presence == .missing } ?? []
        let source = Array((scope?.description ?? "missing").utf8)
        let offset = min(missing.first?.position.utf8Offset ?? 0, source.count)
        let excerpt = String(decoding: source[max(0, offset - 280)..<min(source.count, offset + 280)], as: UTF8.self)
        throw CompilationDiagnostic(
            code: .unsupportedGeneratedValueShape, stage: .validation,
            path: "native._Updates.merging",
            expected: "one mergeUpdate call per compiled slot with its resolved record relation when required",
            actual: "orders=\(ordersMatch) \(orderFailure); parserError=\(merge?.hasError ?? true), missing=\(missing.prefix(8).map { String(describing: $0.tokenKind) }), excerpt=\(excerpt), scopeTail=\(merge?.description.suffix(240) ?? "missing"), mismatch=\(mismatch), actual=\(Array(actualText.dropFirst(max(0, mismatch - 8)).prefix(40))), expected=\(Array(expected.dropFirst(max(0, mismatch - 8)).prefix(40)))",
            nextSafeAction: "Report this native code generation failure."
        )
    }
}

func verifyGeneratedUpdateApplyOutput(
    _ declaration: DeclSyntax?,
    publicFields: [(label: String, field: String, slot: String)],
    hiddenSlots: [String]
) throws {
    let actual = declaration?.as(StructDeclSyntax.self)?.memberBlock.members.compactMap {
        $0.decl.as(FunctionDeclSyntax.self)
    }.first { $0.name.text == "applying" }
    let publicArguments = publicFields.map {
        "\($0.label): \($0.slot) ?? state.state.\($0.field)"
    }.joined(separator: ", ")
    let hiddenArguments = hiddenSlots.map {
        ", \($0): \($0) ?? state.\($0)"
    }.joined()
    let expected = Parser.parse(source: """
    func applying(to state: Snapshot) -> Snapshot {
        Snapshot(state: State(\(publicArguments))\(hiddenArguments))
    }
    """).statements.first?.item.as(FunctionDeclSyntax.self)
    guard let actual, let expected,
          Array(actual.tokens(viewMode: .sourceAccurate)).map(\.text)
            == Array(expected.tokens(viewMode: .sourceAccurate)).map(\.text) else {
        throw CompilationDiagnostic(
            code: .unsupportedGeneratedValueShape, stage: .validation,
            path: "native._Updates.applying",
            expected: "one complete state replacement using each compiled update slot",
            actual: "the generated apply method differs from the checked rule",
            nextSafeAction: "Report this native code generation failure."
        )
    }
}

func verifyGeneratedSourceDefaultDeadlock(_ declaration: DeclSyntax?, required: Bool) throws {
    guard required else { return }
    let expected = Parser.parse(source: "public static var checksDeadlock: \(nativeBoolType) { true }")
        .statements.first?.item.as(VariableDeclSyntax.self)
    guard let actual = declaration?.as(VariableDeclSyntax.self), let expected,
          Array(actual.tokens(viewMode: .sourceAccurate)).map(\.text)
            == Array(expected.tokens(viewMode: .sourceAccurate)).map(\.text) else {
        throw CompilationDiagnostic(code: .unsupportedGeneratedValueShape, stage: .validation,
            path: "native.checking.defaultDeadlock",
            expected: "the authored #spec default checksDeadlock true",
            actual: "the generated Swift checking default differs from the checked rule",
            nextSafeAction: "Report this native checking generation failure.")
    }
}

func verifyGeneratedValidationDelegationOutput(_ declaration: DeclSyntax?) throws {
    let expected = Parser.parse(source: """
    public func visitValidationOutcomes(checking context: inout CheckingContext<CheckingRegisters>,
                                        _ visit: (Action, Self) throws -> \(nativeBoolType),
                                        onEvaluationFailure: (Action, NativeMachineEvaluationError) throws -> \(nativeBoolType)) throws -> \(nativeBoolType) {
        var run: CheckingContext<CheckingRegisters>? = context
        defer { context = run! }
        return try _visitSuccessors(checking: &run, visit, onEvaluationFailure: onEvaluationFailure)
    }
    """).statements.first?.item.as(FunctionDeclSyntax.self)
    guard let actual = declaration?.as(FunctionDeclSyntax.self), let expected,
          Array(actual.tokens(viewMode: .sourceAccurate)).map(\.text)
            == Array(expected.tokens(viewMode: .sourceAccurate)).map(\.text) else {
        throw CompilationDiagnostic(
            code: .unsupportedGeneratedValueShape, stage: .validation,
            path: "native.validation.delegation",
            expected: "forward every successor and exact action failure through the generated checking entry point",
            actual: "the emitted validation entry point differs from the checked rule",
            nextSafeAction: "Report this native validation generation failure."
        )
    }
}

func verifyGeneratedSuccessorOutput(
    _ declaration: DeclSyntax?, actionID: Int, parameters: String, arguments: String,
    configurationParameters: String, configurationArguments: String
) throws {
    let expected = Parser.parse(source: """
    private static func _visitSuccessors\(actionID)(from state: Snapshot\(parameters.isEmpty ? "" : ", " + parameters)\(configurationParameters), checking context: inout CheckingContext<CheckingRegisters>?,
                                                  _ visit: (Snapshot) throws -> Void) throws -> [NativeMachineEvaluationError] {
        var emitted: [Snapshot] = []
        return try _visitUpdates\(actionID)(from: state\(arguments.isEmpty ? "" : ", " + arguments)\(configurationArguments), checking: &context) { updates in
            let candidate = updates.applying(to: state)
            if !emitted.contains(candidate) {
                emitted.append(candidate)
                try visit(candidate)
            }
        }
    }
    """).statements.first?.item.as(FunctionDeclSyntax.self)
    guard let actual = declaration?.as(FunctionDeclSyntax.self), let expected,
          Array(actual.tokens(viewMode: .sourceAccurate)).map(\.text)
            == Array(expected.tokens(viewMode: .sourceAccurate)).map(\.text) else {
        throw CompilationDiagnostic(
            code: .unsupportedGeneratedValueShape, stage: .validation,
            path: "native.action.successor.\(actionID)",
            expected: "apply every complete compiled update and visit each resulting snapshot once",
            actual: "the emitted successor wrapper differs from the checked rule",
            nextSafeAction: "Report this native successor generation failure."
        )
    }
}

struct ScalarBoundRoute {
    struct Binding {
        let label: String
        let name: String
        let type: CompiledValueType
        let members: [CompiledValue]
    }
    let name: String
    let id: Int
    let formalName: String
    let bindings: [Binding]
}

func scalarBoundRoutes(program: CompiledProgram, actions: [GeneratedMachineAPI.Action]) -> [ScalarBoundRoute] {
    actions.compactMap { api in
        let action = program[api.compiledAction]
        guard !action.bindings.isEmpty, isTotalScalarAssignment(action.body),
              action.bindings.count == api.bindings.count,
              api.bindings.allSatisfy(\.isPublic) else { return nil }
        var bindings: [ScalarBoundRoute.Binding] = []
        for (binding, exposed) in zip(action.bindings, api.bindings) {
            guard let type = program.bindingTypes[binding.binder], type == .int || type == .bool,
                  let members = binding.literalMembers, members.count > 1,
                  members.allSatisfy({ member in
                      switch (member, type) {
                      case (.integer, .int), (.boolean, .bool): true
                      default: false
                      }
                  }), let sourceName = program.binderNames[binding.binder] else { return nil }
            bindings.append(.init(label: exposed.swiftIdentifier,
                name: "_\(sourceName)_\(binding.binder.ordinal)", type: type, members: members))
        }
        return ScalarBoundRoute(name: api.swiftIdentifier, id: action.id.ordinal,
            formalName: program.layout.actions[action.id.ordinal].renderedName, bindings: bindings)
    }
}

func verifyGeneratedActionRoutingOutput(
    _ declarations: [DeclSyntax], routes: [(name: String, id: Int, formalName: String)],
    allActions: [(name: String, id: Int, formalName: String, publicBindings: Int)],
    candidates candidatePlans: [(name: String, labels: [String])], configurationArguments: String,
    boundRoutes: [ScalarBoundRoute] = []
) throws {
    func invalid(_ path: String, _ expected: String) -> CompilationDiagnostic {
        CompilationDiagnostic(
            code: .unsupportedGeneratedValueShape, stage: .validation, path: path,
            expected: expected, actual: "the emitted action route or label differs",
            nextSafeAction: "Report this native action routing failure."
        )
    }
    func cases(of name: String) throws -> [String: (pattern: [String], body: CodeBlockItemListSyntax)] {
        let methods = declarations.compactMap { $0.as(FunctionDeclSyntax.self) }.filter {
            $0.name.text == name && $0.signature.parameterClause.parameters.first?.firstName.text == "for"
        }
        guard methods.count == 1, let method = methods.first else {
            throw invalid("native.action.routing.method", "one generated \(name)(for action:) method")
        }
        guard method.body?.statements.count == 1,
              let statement = method.body?.statements.first else {
            throw invalid("native.action.routing.switch", "one direct switch over the selected action")
        }
        let expression: ExprSyntax?
        if case .expr(let value) = statement.item {
            expression = value
        } else {
            expression = statement.item.as(ExpressionStmtSyntax.self)?.expression
        }
        guard let choice = expression?.as(SwitchExprSyntax.self),
              choice.subject.as(DeclReferenceExprSyntax.self)?.baseName.text == "action" else {
            throw invalid("native.action.routing.switch", "one direct switch over the selected action")
        }
        var result: [String: (pattern: [String], body: CodeBlockItemListSyntax)] = [:]
        for element in choice.cases {
            guard let branch = element.as(SwitchCaseSyntax.self),
                  let label = branch.label.as(SwitchCaseLabelSyntax.self),
                  label.caseItems.count == 1, let item = label.caseItems.first,
                  item.whereClause == nil else {
                throw invalid("native.action.routing.switch", "one unconditional case per action")
            }
            let pattern = Array(item.pattern.tokens(viewMode: .sourceAccurate))
            guard pattern.count >= 2, pattern[0].text == "." else {
                throw invalid("native.action.routing.switch", "one named case per action")
            }
            let identifier = pattern[1].sourceIdentifierName
            guard result[identifier] == nil else {
                throw invalid("native.action.routing", "one case per action identity")
            }
            result[identifier] = (pattern.map(\.text), branch.statements)
        }
        return result
    }
    func tokens(_ source: String) -> [String] {
        Array(Parser.parse(source: source).tokens(viewMode: .sourceAccurate))
            .filter { $0.tokenKind != .endOfFile }.map(\.text)
    }
    func scalarDomain(_ binding: ScalarBoundRoute.Binding) -> String {
        let values = binding.members.map { member in
            switch member {
            case .integer(let value): value == Int.min ? "\(nativeIntType).min" : String(value)
            case .boolean(let value): String(value)
            default: ""
            }
        }.joined(separator: ", ")
        return "[\(values)]"
    }
    let dispatched = try cases(of: "_visitSuccessors")
    let labeled = try cases(of: "formalCall")
    let expectedNames = Set(allActions.map { $0.name.filter { $0 != "`" } })
    guard Set(dispatched.keys) == expectedNames, Set(labeled.keys) == expectedNames else {
        throw invalid("native.action.routing", "exactly the compiled action cases")
    }
    for route in routes {
        let name = route.name.filter { $0 != "`" }
        let expectedDispatch = tokens("return try Self._visitSuccessors\(route.id)(from: _execution\(configurationArguments), checking: &context, visit)")
        guard dispatched[name].map({ Array($0.body.tokens(viewMode: .sourceAccurate)).map(\.text) }) == expectedDispatch else {
            throw invalid("native.action.route.\(name)", "the complete successor route for compiled action \(route.id)")
        }
        let expectedLabel = tokens("return FormalActionCall(name: \(String(reflecting: route.formalName)), arguments: [])")
        guard labeled[name].map({ Array($0.body.tokens(viewMode: .sourceAccurate)).map(\.text) }) == expectedLabel else {
            throw invalid("native.action.label.\(name)", "the compiled formal action label \(route.formalName)")
        }
    }
    let directNames = Set(routes.map { $0.name })
    for route in allActions where !directNames.contains(route.name) {
        let name = route.name.filter { $0 != "`" }
        guard let branch = dispatched[name]?.body, branch.count == route.publicBindings + 1,
              Array(branch.dropLast()).allSatisfy({ $0.item.as(GuardStmtSyntax.self) != nil }),
              let call = branch.last,
              Array(call.tokens(viewMode: .sourceAccurate)).map(\.text).starts(with:
                tokens("return try Self._visitSuccessors\(route.id)(from: _execution")) else {
            throw invalid("native.action.route.\(name)", "the selected action reaches compiled successor \(route.id)")
        }
        guard let label = labeled[name]?.body, label.count == 1, let statement = label.first,
              Array(statement.tokens(viewMode: .sourceAccurate)).map(\.text).starts(with:
                tokens("return FormalActionCall(name: \(String(reflecting: route.formalName)), arguments:")) else {
            throw invalid("native.action.label.\(name)", "the compiled formal action label \(route.formalName)")
        }
    }
    for route in boundRoutes {
        let name = route.name.filter { $0 != "`" }
        let pattern = ".\(route.name)(" + route.bindings.map { "\($0.label): let \($0.name)" }.joined(separator: ", ") + ")"
        let guards = route.bindings.map { binding in
            "guard \(scalarDomain(binding)).contains(\(binding.name)) else { return [] }"
        }.joined(separator: "\n")
        let arguments = route.bindings.map { "\($0.name): \($0.name)" }.joined(separator: ", ")
        let dispatch = "\(guards)\nreturn try Self._visitSuccessors\(route.id)(from: _execution, \(arguments)\(configurationArguments), checking: &context, visit)"
        guard dispatched[name]?.pattern == tokens(pattern),
              dispatched[name].map({ Array($0.body.tokens(viewMode: .sourceAccurate)).map(\.text) }) == tokens(dispatch) else {
            throw invalid("native.action.route.\(name)", "the complete bound successor route for compiled action \(route.id)")
        }
        let values = route.bindings.map { binding in
            binding.type == .int
                ? "SwiftTLA._nativeFormalInt(\(binding.name))"
                : "SwiftTLA.TLAValue.bool(\(binding.name))"
        }.joined(separator: ", ")
        let formal = "return FormalActionCall(name: \(String(reflecting: route.formalName)), arguments: [\(values)])"
        guard labeled[name]?.pattern == tokens(pattern),
              labeled[name].map({ Array($0.body.tokens(viewMode: .sourceAccurate)).map(\.text) }) == tokens(formal) else {
            throw invalid("native.action.label.\(name)", "the complete bound formal call for \(route.formalName)")
        }
    }
    let methods = declarations.compactMap { $0.as(FunctionDeclSyntax.self) }
    let successorWrappers = methods.filter {
        $0.name.text == "_successors"
            && $0.signature.parameterClause.parameters.first?.firstName.text == "for"
    }
    let expectedSuccessorWrappers = [
        """
        private func _successors(for action: Action) throws -> [Snapshot] {
            var context: CheckingContext<CheckingRegisters>?
            return try _successors(for: action, checking: &context)
        }
        """,
        """
        private func _successors(for action: Action, checking context: inout CheckingContext<CheckingRegisters>?) throws -> [Snapshot] {
            var result: [Snapshot] = []
            let failures = try _visitSuccessors(for: action, checking: &context) { SwiftTLA._appendNativeOutcome(&result, $0) }
            if let failure = failures.first { throw failure }
            return result
        }
        """,
    ]
    guard successorWrappers.count == expectedSuccessorWrappers.count,
          expectedSuccessorWrappers.allSatisfy({ expected in
              successorWrappers.filter {
                  Array($0.tokens(viewMode: .sourceAccurate)).map(\.text) == tokens(expected)
              }.count == 1
          }) else {
        throw invalid("native.action.successorRoute", "both wrappers preserve the complete successor list")
    }
    let send = methods.filter { $0.name.text == "send" }
    let expectedSend = tokens("""
        public mutating func send(_ action: Action) throws -> Transition {
            let next = try SwiftTLA._singleNativeOutcome(
                _successors(for: action), missing: .noMatchingSuccessor, ambiguous: .ambiguousAction)
            let before = state
            _execution = next
            return Transition(action: action, before: before, after: state)
        }
        """)
    guard send.count == 1,
          Array(send[0].tokens(viewMode: .sourceAccurate)).map(\.text) == expectedSend else {
        throw invalid("native.action.send", "the public send applies exactly one selected successor")
    }
    let candidates = methods.filter { $0.name.text == "_actions" }
    let expectedCandidates = """
        var result: [Action] = []
        try _visitActionCandidates { result.append($0) }
        return result
        """
    guard candidates.count == 1, let candidateBody = candidates.first?.body?.statements,
          Array(candidateBody.tokens(viewMode: .sourceAccurate)).map(\.text)
            == tokens(expectedCandidates) else {
        throw invalid("native.action.candidates", "the public action list delegates to the candidate visitor")
    }
    let visitors = methods.filter {
        $0.name.text == "_visitSuccessors"
            && $0.signature.parameterClause.parameters.last?.firstName.text == "onEvaluationFailure"
    }
    let failureVisitor = Parser.parse(source: """
    private func _visitSuccessors(checking context: inout CheckingContext<CheckingRegisters>?,
                                  _ visit: (Action, Self) throws -> \(nativeBoolType),
                                  onEvaluationFailure: (Action, NativeMachineEvaluationError) throws -> \(nativeBoolType)) throws -> \(nativeBoolType) {
        var found = false
        do {
            func _visitAction(_ action: Action) throws {
                var callbackFailed = false
                var failures: [NativeMachineEvaluationError] = []
                do {
                    failures = try _visitSuccessors(for: action, checking: &context) { execution in
                        found = true
                        do {
                            if try !visit(action, Self(execution: execution\(configurationArguments))) {
                                throw _StopSuccessorTraversal()
                            }
                        } catch {
                            callbackFailed = true
                            throw error
                        }
                    }
                } catch let reason as NativeMachineEvaluationError where !callbackFailed && reason.isModelEvaluationFailure {
                    failures.append(reason)
                } catch {
                    throw error
                }
                for reason in failures {
                    if try !onEvaluationFailure(action, reason) {
                        throw _StopSuccessorTraversal()
                    }
                }
            }
            try _visitActionCandidates(_visitAction)
        } catch is _StopSuccessorTraversal {
        }
        return found
    }
    """).statements.first?.item.as(FunctionDeclSyntax.self)
    guard visitors.count == 1, let visitor = visitors.first, let failureVisitor,
          Array(visitor.tokens(viewMode: .sourceAccurate)).map(\.text)
            == Array(failureVisitor.tokens(viewMode: .sourceAccurate)).map(\.text) else {
        throw invalid("native.action.failureRouting",
            "preserve every successor and forward its exact action and evaluation failure")
    }
    let sources = methods.filter { $0.name.text == "_visitActionCandidates" }
    guard sources.count == 1, let body = sources.first?.body?.statements,
          body.count == candidatePlans.count else {
        throw invalid("native.action.candidateSource", "one candidate block per compiled action")
    }
    for (statement, plan) in zip(body, candidatePlans) {
        let bound = boundRoutes.first { $0.name == plan.name }
        guard bound == nil || bound?.bindings.count == plan.labels.count else {
            throw invalid("native.action.candidateSource", "every checked domain binds one candidate argument")
        }
        guard let action = statement.item.as(DoStmtSyntax.self), action.catchClauses.isEmpty else {
            throw invalid("native.action.candidateSource", "one unguarded candidate block for \(plan.name)")
        }
        var statements = action.body.statements
        var boundNames: [String] = []
        for index in plan.labels.indices {
            guard statements.count == 1,
                  let loop = statements.first?.item.as(ForStmtSyntax.self),
                  let name = loop.pattern.as(IdentifierPatternSyntax.self)?.identifier.text,
                  loop.whereClause == nil, loop.tryKeyword == nil, loop.awaitKeyword == nil else {
                throw invalid("native.action.candidateSource", "one ordered binding loop for \(plan.name)")
            }
            if let binding = bound?.bindings[index],
               name != binding.name ||
               Array(loop.sequence.tokens(viewMode: .sourceAccurate)).map(\.text) != tokens(scalarDomain(binding)) {
                throw invalid("native.action.candidateSource", "the compiled literal domain binds \(binding.name)")
            }
            boundNames.append(name)
            statements = loop.body.statements
        }
        let arguments = zip(plan.labels, boundNames).map { "\($0.0): \($0.1)" }.joined(separator: ", ")
        let candidate = ".\(plan.name)" + (arguments.isEmpty ? "" : "(\(arguments))")
        guard statements.count == 1, let call = statements.first,
              Array(call.tokens(viewMode: .sourceAccurate)).map(\.text)
                == tokens("try visit(\(candidate))") else {
            throw invalid("native.action.candidateSource", "the bound values reach \(plan.name) exactly once")
        }
    }
}

private func isTotalScalarAssignment(_ root: CompiledActionExpr) -> Bool {
    func scalar(_ expression: CompiledExpression) -> Bool {
        guard expression.children.isEmpty else { return false }
        switch expression.operation {
        case .stateVariable, .boundValue:
            return expression.resultType == .int || expression.resultType == .bool
        case .value(.integer): return expression.resultType == .int
        case .value(.boolean): return expression.resultType == .bool
        default: return false
        }
    }
    var pending = [root]
    while let node = pending.popLast() {
        switch node {
        case .define(_, let value, let body):
            guard scalar(value) else { return false }
            pending.append(body)
        case .and(let left, let right):
            pending.append(right)
            pending.append(left)
        case .assign(_, let value):
            guard scalar(value) else { return false }
        case .unchanged: break
        case .guard_(let value):
            guard value.operation == .value(.boolean(true)), value.resultType == .bool,
                  value.children.isEmpty else { return false }
        default: return false
        }
    }
    return true
}

func verifyGeneratedActionWriteOutput(
    _ declaration: DeclSyntax?, action: CompiledActionExpr, program: CompiledProgram,
    stateFields: [VariableID: String],
    parts: [(id: Int, slot: String, value: String)],
    conditions: [(id: Int, value: String)] = [], requireScalarLeaves: Bool = false,
    externalBindings: [CompiledActionBinding] = []
) throws {
    guard let visitor = declaration?.as(FunctionDeclSyntax.self),
          visitor.body != nil else {
        throw CompilationDiagnostic(
            code: .unsupportedGeneratedValueShape, stage: .validation,
            path: "native.action.write", expected: "a generated update visitor",
            actual: "missing update visitor", nextSafeAction: "Report this native code generation failure."
        )
    }
    func invalid(_ path: String, _ expected: String, _ actual: String) -> CompilationDiagnostic {
        CompilationDiagnostic(
            code: .unsupportedGeneratedValueShape, stage: .validation, path: path,
            expected: expected, actual: actual,
            nextSafeAction: "Report this native code generation failure."
        )
    }
    var externalScalarNames: Set<String> = []
    for binding in externalBindings {
        let type = program.bindingTypes[binding.binder]
        // shortcut: only scalar outer binders have an independent leaf rule; extend this when other value encodings are checked.
        guard type == .int || type == .bool else { continue }
        guard let sourceName = program.binderNames[binding.binder] else {
            throw invalid("native.action.parameter", "a compiled scalar binder name", "missing binder")
        }
        let name = "_\(sourceName)_\(binding.binder.ordinal)"
        let matches = visitor.signature.parameterClause.parameters.filter {
            $0.firstName.text == name &&
                Array($0.type.tokens(viewMode: .sourceAccurate)).map(\.text) == (type == .int ? nativeIntTypeTokens : nativeBoolTypeTokens)
        }
        guard matches.count == 1 else {
            throw invalid("native.action.parameter", "one typed outer parameter for \(name)", "missing or wrong type")
        }
        externalScalarNames.insert(name)
    }
    let syntaxTokens = Array(visitor.tokens(viewMode: .sourceAccurate))
    let visitorTokens = syntaxTokens.map(\.text)
    var tokenDepths: [Int] = []
    tokenDepths.reserveCapacity(visitorTokens.count)
    var depth = 0
    for token in visitorTokens {
        tokenDepths.append(depth)
        if token == "{" { depth += 1 }
        if token == "}" { depth -= 1 }
    }
    var bodies: [Int: [String]] = [:]
    var firstStatements: [Int: Syntax] = [:]
    var infallibleParts: Set<Int> = []
    var parameters: [Int: [String]] = [:]
    var coveredPartTokens = 0
    for index in visitorTokens.indices where visitorTokens[index] == "func" && tokenDepths[index] == 1 {
        let nameIndex = index + 1
        guard nameIndex < visitorTokens.count else { continue }
        let name = visitorTokens[nameIndex]
        guard name.hasPrefix("_actionPart") else { continue }
        guard nameIndex + 1 < visitorTokens.count,
              let id = Int(name.dropFirst("_actionPart".count)), bodies[id] == nil,
              let open = visitorTokens[(nameIndex + 1)...].firstIndex(of: "{") else {
            throw invalid("native.action.parts", "one unique local function per action node", name)
        }
        var depth = 1
        var close = open + 1
        while close < visitorTokens.count && depth > 0 {
            if visitorTokens[close] == "{" { depth += 1 }
            if visitorTokens[close] == "}" { depth -= 1 }
            close += 1
        }
        guard depth == 0 else {
            throw invalid("native.action.parts", "a closed body for \(name)", "missing closing brace")
        }
        guard visitorTokens[nameIndex + 1] == "(" else {
            throw invalid("native.action.parts", "parameters for \(name)", "missing parameter list")
        }
        var parameterDepth = 0
        var names: [String] = []
        for position in (nameIndex + 1)..<open {
            let token = visitorTokens[position]
            if token == "(" { parameterDepth += 1 }
            if token == ")" { parameterDepth -= 1 }
            if parameterDepth == 1 && token == "_" && position + 2 < open &&
                visitorTokens[position + 2] == ":" {
                names.append(visitorTokens[position + 1])
            }
        }
        guard parameterDepth == 0 else {
            throw invalid("native.action.parts", "closed parameters for \(name)", "malformed parameter list")
        }
        parameters[id] = names
        let wrapped = Array(visitorTokens[(open + 1)..<(close - 1)])
        let catchSuffix = ["}", "catch", "let", "failure", "as", "NativeMachineEvaluationError",
                           "where", "failure", ".", "isModelEvaluationFailure",
                           "{", "failures", ".", "append", "(", "failure", ")", "}"]
        if wrapped == ["return"] {
            infallibleParts.insert(id)
            bodies[id] = wrapped
            firstStatements[id] = syntaxTokens[open + 1].parent
        } else {
            guard wrapped.starts(with: ["do", "{"]), wrapped.count > catchSuffix.count + 2,
              wrapped.suffix(catchSuffix.count) == catchSuffix else {
                throw invalid("native.action.failures.\(id)",
                    "retain every reached model failure after its action part", "missing or changed failure collection")
            }
            bodies[id] = Array(wrapped.dropFirst(2).dropLast(catchSuffix.count))
            firstStatements[id] = syntaxTokens[open + 3].parent
        }
        coveredPartTokens += close - index
    }
    func envelopeTokens(_ source: String) -> [String] {
        let proof = Parser.parse(source: "func proof() {\n\(source)\n}")
            .statements.first?.item.as(FunctionDeclSyntax.self)
        return proof?.body?.statements.tokens(viewMode: .sourceAccurate).map(\.text) ?? []
    }
    let failureBinding: String
    if case .guard_(let predicate) = action, predicate.booleanConstant == false {
        failureBinding = "let"
    } else {
        failureBinding = "var"
    }
    let expectedPrefix = envelopeTokens("""
    \(failureBinding) failures: [NativeMachineEvaluationError] = []
    func emit(_ update: _Updates) throws {
        do { try _emit(update) }
        catch { throw _StopSuccessorTraversal(cause: error) }
    }
    """)
    let expectedEntry = envelopeTokens("""
    do { try _actionPart0(_Updates(), emit) }
    catch let stop as _StopSuccessorTraversal {
        if let cause = stop.cause { throw cause }
        throw stop
    }
    return failures
    """)
    guard let bodyOpen = visitorTokens.firstIndex(of: "{"),
          visitorTokens.last == "}",
          let callback = visitor.signature.parameterClause.parameters.last,
          callback.firstName.text == "_", callback.secondName?.text == "_emit",
          callback.type.tokens(viewMode: .sourceAccurate).map(\.text)
            == ["(", "_Updates", ")", "throws", "->", "Void"],
          visitor.signature.returnClause?.type.tokens(viewMode: .sourceAccurate).map(\.text)
            == ["[", "NativeMachineEvaluationError", "]"],
          !expectedPrefix.isEmpty, !expectedEntry.isEmpty,
          visitorTokens.dropFirst(bodyOpen + 1).starts(with: expectedPrefix),
          visitorTokens.dropLast().suffix(expectedEntry.count) == expectedEntry,
          coveredPartTokens + expectedPrefix.count + expectedEntry.count == visitorTokens.count - bodyOpen - 2 else {
        throw invalid("native.action.entry", "checked failure collection, action parts and one root call",
            "unrecognized tokens in the generated visitor")
    }

    var pending: [(id: Int, node: CompiledActionExpr)] = [(0, action)]
    var expectedChildren: [Int: [Int]] = [:]
    var alternatives: [Int] = []
    var conjunctions: [Int] = []
    var conditionals: [Int] = []
    var conditionalPredicates: [Int: CompiledExpression] = [:]
    var guards: [(id: Int, predicate: CompiledExpression)] = []
    var definitions: [(id: Int, child: Int, value: CompiledExpression)] = []
    var assignments: [Int: (variable: VariableID, value: CompiledExpression)] = [:]
    var frames: [Int: VariableID] = [:]
    var nextID = 1
    var expectedWriteCount = 0
    while let (id, node) = pending.popLast() {
        switch node {
        case .assign(let variable, let value):
            expectedWriteCount += 1
            expectedChildren[id] = []
            assignments[id] = (variable, value)
        case .unchanged(let variable):
            expectedWriteCount += 1
            expectedChildren[id] = []
            frames[id] = variable
        case .guard_(let predicate):
            expectedChildren[id] = []
            guards.append((id, predicate))
        case .existsAction(_, _, let body):
            expectedChildren[id] = [nextID]
            pending.append((nextID, body))
            nextID += 1
        case .define(_, let value, let body):
            expectedChildren[id] = [nextID]
            definitions.append((id, nextID, value))
            pending.append((nextID, body))
            nextID += 1
        case .ifElse(let predicate, let yes, let no):
            expectedChildren[id] = [nextID, nextID + 1]
            conditionals.append(id)
            conditionalPredicates[id] = predicate
            pending.append((nextID, yes))
            pending.append((nextID + 1, no))
            nextID += 2
        case .and(let lhs, let rhs):
            expectedChildren[id] = [nextID + 1, nextID]
            conjunctions.append(id)
            pending.append((nextID, rhs))
            pending.append((nextID + 1, lhs))
            nextID += 2
        case .or(let lhs, let rhs):
            expectedChildren[id] = [nextID, nextID + 1]
            alternatives.append(id)
            pending.append((nextID, rhs))
            pending.append((nextID + 1, lhs))
            nextID += 2
        }
    }
    guard bodies.count == expectedChildren.count else {
        throw invalid("native.action.parts", "one generated function per compiled action node",
            "found \(bodies.count) functions for \(expectedChildren.count) nodes")
    }
    guard infallibleParts == Set(guards.filter { $0.predicate.booleanConstant == false }.map(\.id)) else {
        throw invalid("native.action.failures", "only constant-false guards omit failure collection",
            "the unwrapped parts differ from the infallible compiled guards")
    }
    for (id, children) in expectedChildren {
        guard let tokens = bodies[id] else {
            throw invalid("native.action.part.\(id)", "a generated function for the compiled node", "missing")
        }
        let calls = tokens.enumerated().compactMap { index, token -> Int? in
            guard index + 1 < tokens.count, tokens[index + 1] == "(",
                  token.hasPrefix("_actionPart") else { return nil }
            return Int(token.dropFirst("_actionPart".count))
        }
        guard calls == children else {
            throw invalid("native.action.part.\(id)", "ordered child calls \(children)", "child calls \(calls)")
        }
    }
    func stringComparisonSource(_ expression: CompiledExpression, parameters: [String]) -> String? {
        guard expression.resultType == .bool, expression.children.count == 2,
              expression.children.allSatisfy({ $0.resultType == .string }) else { return nil }
        let symbol: String
        switch expression.operation {
        case .equal: symbol = "=="
        case .notEqual: symbol = "!="
        default: return nil
        }
        func operand(_ node: CompiledExpression) -> String? {
            switch node.operation {
            case .stateVariable(let variable):
                return stateFields[variable].map { "state.state.\($0)" }
            case .boundValue(let binding) where program.bindingTypes[binding] == .string:
                guard let name = program.binderNames[binding].map({ "_\($0)_\(binding.ordinal)" }),
                      parameters.contains(name) else { return nil }
                return name
            case .value(.string(let value)):
                return "SwiftTLA._NativeString(formalString: \(String(reflecting: value)))"
            default: return nil
            }
        }
        guard let left = operand(expression.children[0]),
              let right = operand(expression.children[1]) else { return nil }
        return "(\(left) \(symbol) \(right))"
    }
    func slotName(_ id: VariableID) -> String? {
        guard let declaration = program.layout.variables.first(where: { $0.id == id })?.declaration else {
            return nil
        }
        let name = String(declaration.name.unicodeScalars.map { scalar -> Character in
            switch scalar.value {
            case 65...90, 97...122, 48...57, 95: Character(String(scalar))
            default: "_"
            }
        })
        return "_value_\(name)_\(id.ordinal)"
    }
    func controlComparisonSource(_ expression: CompiledExpression) -> String? {
        guard expression.resultType == .bool, expression.children.count == 2,
              expression.children.allSatisfy({ $0.resultType == .controlLocation }) else { return nil }
        let symbol: String
        switch expression.operation {
        case .equal: symbol = "=="
        case .notEqual: symbol = "!="
        default: return nil
        }
        func operand(_ node: CompiledExpression) -> String? {
            switch node.operation {
            case .stateVariable(let id) where program.layout.variables.contains(where: {
                $0.id == id && $0.declaration.origin == .programCounter
            }):
                return slotName(id).map { "state.\($0)" }
            case .controlLocation(let id) where program.layout.controlLocations.contains(where: { $0.id == id }):
                return "_ControlLocation.location\(id.ordinal)"
            default: return nil
            }
        }
        guard let left = operand(expression.children[0]),
              let right = operand(expression.children[1]) else { return nil }
        return "(\(left) \(symbol) \(right))"
    }
    func directScalarTokens(_ expression: CompiledExpression, parameters: [String]) -> [String]? {
        guard expression.resultType == .int || expression.resultType == .bool else { return nil }
        switch expression.operation {
        case .stateVariable(let variable):
            return stateFields[variable].map { ["state", ".", "state", ".", $0] }
        case .tupleLength where expression.resultType == .int && expression.children.count == 1:
            let sequence = expression.children[0]
            guard case .array = sequence.resultType,
                  case .stateVariable(let variable) = sequence.operation,
                  let field = stateFields[variable] else { return nil }
            return ["(", "state", ".", "state", ".", field, ".", "count", ")"]
        case .boundValue(let binding) where program.bindingTypes[binding] == expression.resultType:
            if let parameter = program.layout.parameters.first(where: { $0.binder == binding }) {
                return Parser.parse(source: "configuration.`\(parameter.reference.name)`")
                    .tokens(viewMode: .sourceAccurate).map(\.text).filter { !$0.isEmpty }
            }
            guard let name = program.binderNames[binding].map({ "_\($0)_\(binding.ordinal)" }),
                  parameters.contains(name) || externalScalarNames.contains(name) else { return nil }
            return [name]
        case .value(.integer(let integer)) where expression.resultType == .int:
            if integer == Int.min { return nativeIntTypeTokens + [".", "min"] }
            return integer < 0 ? ["-", String(integer.magnitude)] : [String(integer)]
        case .value(.boolean(let value)) where expression.resultType == .bool:
            return [value ? "true" : "false"]
        default:
            return nil
        }
    }
    func arithmeticIntTokens(_ expression: CompiledExpression, parameters: [String]) -> [String]? {
        func checkedOperation(_ operation: CompiledOperation) -> (name: String, rightFirst: Bool, arity: Int)? {
            switch operation {
            case .add: return ("add", false, 2)
            case .subtract: return ("subtract", false, 2)
            case .multiply: return ("multiply", false, 2)
            case .divide, .integerDivide: return ("divide", true, 2)
            case .modulo: return ("modulo", true, 2)
            case .negate: return ("negate", false, 1)
            default: return nil
            }
        }
        guard expression.resultType == .int,
              let rootOperation = checkedOperation(expression.operation) else { return nil }
        if rootOperation.rightFirst, expression.children.count == 2,
           expression.children.allSatisfy({ child in
               guard child.resultType == .int, child.children.isEmpty,
                     case .value(.integer) = child.operation else { return false }
               return true
           }),
           let left = directScalarTokens(expression.children[0], parameters: parameters),
           let right = directScalarTokens(expression.children[1], parameters: parameters) {
            return ["(", "try", "SwiftTLA", ".", "_NativeMachineOperations", ".", rootOperation.name, "("]
                + left + [","] + right + [")", ")"]
        }
        var pending: [(expression: CompiledExpression, expanded: Bool)] = [(expression, false)]
        var values: [String] = []
        var statements: [String] = []
        var ordinal = 0
        while let (node, expanded) = pending.popLast() {
            guard node.resultType == .int else { return nil }
            let value: [String]
            if let operation = checkedOperation(node.operation) {
                guard node.children.count == operation.arity else { return nil }
                if !expanded {
                    pending.append((node, true))
                    let order = operation.rightFirst ? Array(node.children.reversed()) : node.children
                    pending.append(contentsOf: order.reversed().map { ($0, false) })
                    continue
                }
                guard values.count >= operation.arity else { return nil }
                let operands = Array(values.suffix(operation.arity))
                values.removeLast(operation.arity)
                let arguments = operation.rightFirst ? Array(operands.reversed()) : operands
                let helper = operation.name == "add" ? ["_nativeIntAdd"] : ["_NativeMachineOperations", ".", operation.name]
                value = ["try", "SwiftTLA", "."] + helper + ["("] +
                    arguments.enumerated().flatMap { index, argument in
                        index == 0 ? [argument] : [",", argument]
                    } + [")"]
            } else {
                guard let direct = directScalarTokens(node, parameters: parameters) else { return nil }
                value = direct
            }
            let name = "_arithmetic\(ordinal)"
            ordinal += 1
            statements += ["let", name, ":"] + nativeIntTypeTokens + ["="] + value
            values.append(name)
        }
        guard values.count == 1, let result = values.first else { return nil }
        return ["(", "try", "{", "(", ")", "throws", "->"] + nativeIntTypeTokens + ["in"] + statements +
            ["return", result, "}", "(", ")", ")"]
    }
    func rangeMembershipSource(_ expression: CompiledExpression, parameters: [String]) -> String? {
        guard expression.operation == .in, expression.resultType == .bool,
              expression.children.count == 2, expression.children[0].resultType == .int,
              expression.children[1].resultType == .set(.int) else { return nil }
        var pending = [expression.children[1]]
        var hasRange = false
        while let node = pending.popLast() {
            if node.operation == .integerRange { hasRange = true; break }
            switch node.operation {
            case .union, .intersection, .setDifference: pending += node.children
            case .ifThenElse: pending += node.children.dropFirst()
            default: break
            }
        }
        guard hasRange else { return nil }
        func scalar(_ node: CompiledExpression) -> String? {
            (directScalarTokens(node, parameters: parameters)
                ?? arithmeticIntTokens(node, parameters: parameters)).map { $0.joined(separator: " ") }
        }
        var ordinal = 0
        func domain(_ node: CompiledExpression) -> (declaration: String, call: String)? {
            guard node.resultType == .set(.int) else { return nil }
            let name = "_membershipPredicate\(ordinal)"
            ordinal += 1
            let body: String
            switch node.operation {
            case .integerRange:
                guard node.children.count == 2,
                      let lower = scalar(node.children[0]), let upper = scalar(node.children[1]) else { return nil }
                body = "let bounds = (\(lower), \(upper))\nreturn { candidate in bounds.0 <= candidate && candidate <= bounds.1 }"
            case .integerSet:
                body = "return { _ in true }"
            case .setLiteral:
                let members = node.children.compactMap(scalar)
                guard members.count == node.children.count else { return nil }
                body = "let members = Set<\(nativeIntType)>([\(members.joined(separator: ", "))])\nreturn { members.contains($0) }"
            case .union, .intersection, .setDifference:
                guard node.children.count == 2,
                      let left = domain(node.children[0]), let right = domain(node.children[1]) else { return nil }
                let operation = node.operation == .union ? "left(candidate) || right(candidate)"
                    : node.operation == .intersection ? "left(candidate) && right(candidate)" : "left(candidate) && !right(candidate)"
                body = "\(left.declaration)\n\(right.declaration)\nlet left = \(left.call)\nlet right = \(right.call)\nreturn { candidate in \(operation) }"
            case .ifThenElse:
                guard node.children.count == 3,
                      let first = domain(node.children[1]), let second = domain(node.children[2]),
                      let condition = scalarPredicateTokens(node.children[0], parameters: parameters) else { return nil }
                body = "\(first.declaration)\n\(second.declaration)\nif \(condition.joined(separator: " ")) { return \(first.call) }\nreturn \(second.call)"
            default:
                // shortcut: callable domain leaves need their own output rule before universal query claims.
                return nil
            }
            return ("func \(name)() throws -> ((\(nativeIntType)) -> \(nativeBoolType)) {\n\(body)\n}", "try \(name)()")
        }
        guard let predicate = domain(expression.children[1]), let candidate = scalar(expression.children[0]) else { return nil }
        return "(try { () throws -> \(nativeBoolType) in\n\(predicate.declaration)\nlet contains = \(predicate.call)\nlet candidate = \(candidate)\nreturn contains(candidate)\n}())"
    }
    func scalarPredicateTokens(_ expression: CompiledExpression, parameters: [String]) -> [String]? {
        if let source = controlComparisonSource(expression) {
            return Parser.parse(source: source).tokens(viewMode: .sourceAccurate)
                .map(\.text).filter { !$0.isEmpty }
        }
        if let source = stringComparisonSource(expression, parameters: parameters) {
            return Parser.parse(source: source).tokens(viewMode: .sourceAccurate)
                .map(\.text).filter { !$0.isEmpty }
        }
        guard expression.resultType == .bool else { return nil }
        var pending: [(expression: CompiledExpression, expanded: Bool)] = [(expression, false)]
        var values: [[String]] = []
        while let (node, expanded) = pending.popLast() {
            if case .not = node.operation {
                guard let source = shortCircuitPredicateSource(node, parameters: parameters) else { return nil }
                values.append(Parser.parse(source: source).tokens(viewMode: .sourceAccurate)
                    .map(\.text).filter { !$0.isEmpty })
                continue
            }
            if let direct = directScalarTokens(node, parameters: parameters)
                ?? arithmeticIntTokens(node, parameters: parameters) {
                values.append(direct)
                continue
            }
            if case .in = node.operation {
                if let source = rangeMembershipSource(node, parameters: parameters) {
                    values.append(Parser.parse(source: source).tokens(viewMode: .sourceAccurate)
                        .map(\.text).filter { !$0.isEmpty })
                    continue
                }
                guard node.children.count == 2,
                      case .set(let elementType) = node.children[1].resultType,
                      elementType == node.children[0].resultType,
                      elementType == .int || elementType == .bool,
                      let candidate = directScalarTokens(node.children[0], parameters: parameters)
                        ?? arithmeticIntTokens(node.children[0], parameters: parameters) else { return nil }
                let membersSource: String
                switch node.children[1].operation {
                case .setLiteral:
                    var members: [String] = []
                    for member in node.children[1].children {
                        guard member.resultType == elementType,
                              let tokens = directScalarTokens(member, parameters: parameters)
                                ?? arithmeticIntTokens(member, parameters: parameters) else { return nil }
                        members.append(tokens.joined(separator: " "))
                    }
                    let typeName = elementType == .int ? nativeIntType : nativeBoolType
                    membersSource = "Set<\(typeName)>([\(members.joined(separator: ", "))])"
                case .boundValue(let binding):
                    guard program.bindingTypes[binding] == node.children[1].resultType,
                          let parameter = program.layout.parameters.first(where: { $0.binder == binding })
                    else { return nil }
                    membersSource = "configuration.`\(parameter.reference.name)`"
                case .stateVariable(let variable):
                    guard let field = stateFields[variable] else { return nil }
                    membersSource = "state.state.\(field)"
                default: return nil
                }
                let source = "(\(membersSource).contains(\(candidate.joined(separator: " "))))"
                values.append(Parser.parse(source: source).tokens(viewMode: .sourceAccurate)
                    .map(\.text).filter { !$0.isEmpty })
                continue
            }
            let symbol: String
            switch node.operation {
            case .equal: symbol = "=="
            case .notEqual: symbol = "!="
            case .lessThan: symbol = "<"
            case .lessOrEqual: symbol = "<="
            case .greaterThan: symbol = ">"
            case .greaterOrEqual: symbol = ">="
            default: return nil
            }
            guard node.resultType == .bool, node.children.count == 2 else { return nil }
            let operandType = node.children[0].resultType
            guard operandType == node.children[1].resultType,
                  operandType == .int || ((symbol == "==" || symbol == "!=") && operandType == .bool)
            else { return nil }
            if !expanded {
                pending.append((node, true))
                pending.append(contentsOf: node.children.reversed().map { ($0, false) })
                continue
            }
            guard values.count >= 2 else { return nil }
            let operands = Array(values.suffix(2))
            values.removeLast(2)
            values.append(["("] + operands[0] + [symbol] + operands[1] + [")"])
        }
        return values.count == 1 ? values[0] : nil
    }
    func booleanPredicateNodes(_ root: CompiledExpression) -> [CompiledExpression]? {
        guard root.resultType == .bool else { return nil }
        switch root.operation {
        case .and, .or, .ifThenElse, .not: break
        default: return nil
        }
        var ordered: [CompiledExpression] = []
        var seen: Set<CompiledExpression> = []
        var pending = [root]
        while let node = pending.popLast() {
            guard seen.insert(node).inserted else { continue }
            ordered.append(node)
            switch node.operation {
            case .and, .or:
                guard node.resultType == .bool, node.children.count == 2,
                      node.children.allSatisfy({ $0.resultType == .bool }) else { return nil }
                pending.append(contentsOf: node.children.reversed())
            case .ifThenElse:
                guard node.resultType == .bool, node.children.count == 3,
                      node.children.allSatisfy({ $0.resultType == .bool }) else { return nil }
                pending.append(contentsOf: node.children.reversed())
            case .not:
                guard node.resultType == .bool, node.children.count == 1,
                      node.children[0].resultType == .bool else { return nil }
                pending.append(node.children[0])
            default: break
            }
        }
        return ordered
    }
    func shortCircuitPredicateSource(
        _ root: CompiledExpression, parameters: [String], opaqueLeaves: Set<Int> = []
    ) -> String? {
        guard let ordered = booleanPredicateNodes(root) else { return nil }
        let identifiers = Dictionary(uniqueKeysWithValues: ordered.enumerated().map { ($0.element, $0.offset) })
        let declarations = ordered.compactMap { node -> String? in
            let id = identifiers[node]!
            let body: String
            switch node.operation {
            case .and, .or:
                let left = identifiers[node.children[0]]!
                let right = identifiers[node.children[1]]!
                let operation: String = if case .and = node.operation { "booleanAnd" } else { "booleanOr" }
                body = "return try SwiftTLA._NativeMachineOperations.\(operation)({ try _predicate\(left)() }, { try _predicate\(right)() })"
            case .ifThenElse:
                let condition = identifiers[node.children[0]]!
                let yes = identifiers[node.children[1]]!
                let no = identifiers[node.children[2]]!
                body = "return try SwiftTLA._NativeMachineOperations.booleanIf({ try _predicate\(condition)() }, ifTrue: { try _predicate\(yes)() }, ifFalse: { try _predicate\(no)() })"
            case .not:
                let child = identifiers[node.children[0]]!
                body = "return try SwiftTLA._NativeMachineOperations.booleanNot { try _predicate\(child)() }"
            default:
                // Preserve literal spelling; joining token text would split a String literal.
                if let source = stringComparisonSource(node, parameters: parameters) {
                    body = "return \(source)"
                } else if let tokens = scalarPredicateTokens(node, parameters: parameters) {
                    body = "return \(tokens.joined(separator: " "))"
                } else if opaqueLeaves.contains(id) {
                    body = "return __uncheckedPredicateLeaf\(id)__"
                } else {
                    return nil
                }
            }
            return "func _predicate\(id)() throws -> \(nativeBoolType) { \(body) }"
        }
        guard declarations.count == ordered.count else { return nil }
        return "(try { () throws -> \(nativeBoolType) in \(declarations.joined(separator: "\n")) return try _predicate0() }())"
    }
    func checkedBooleanTree(
        _ root: CompiledExpression, parameters: [String], actual: [String]
    ) -> (source: String, actual: [String])? {
        guard let ordered = booleanPredicateNodes(root) else { return nil }
        let opaque = Set(ordered.indices.filter { index in
            let node = ordered[index]
            switch node.operation {
            case .and, .or, .ifThenElse, .not: return false
            default: return scalarPredicateTokens(node, parameters: parameters) == nil
            }
        })
        guard !opaque.isEmpty else {
            return shortCircuitPredicateSource(root, parameters: parameters).map { ($0, actual) }
        }

        // shortcut: check the Boolean skeleton while treating unsupported leaves as opaque.
        // Their values still need independent output links before a full fidelity claim.
        var braceStack: [Int] = []
        var closeByOpen: [Int: Int] = [:]
        var declarations: [(depth: Int, open: Int)] = []
        let signature = ["(", ")", "throws", "->"] + nativeBoolTypeTokens + ["{"]
        for index in actual.indices {
            if actual[index] == "func", index + 2 + signature.count <= actual.count,
               actual[index + 1].hasPrefix("_predicate"),
               Int(actual[index + 1].dropFirst("_predicate".count)) != nil,
               Array(actual[(index + 2)..<(index + 2 + signature.count)]) == signature {
                declarations.append((braceStack.count, index + 1 + signature.count))
            }
            if actual[index] == "{" { braceStack.append(index) }
            if actual[index] == "}" {
                guard let open = braceStack.popLast() else { return nil }
                closeByOpen[open] = index
            }
        }
        guard braceStack.isEmpty,
              let outerDepth = declarations.map(\.depth).min() else { return nil }
        let outer = declarations.filter { $0.depth == outerDepth }
        guard outer.count == ordered.count,
              let source = shortCircuitPredicateSource(root, parameters: parameters, opaqueLeaves: opaque)
        else { return nil }
        var redacted = actual
        for index in opaque.sorted(by: >) {
            let function = outer[index]
            guard let close = closeByOpen[function.open],
                  function.open + 2 < close,
                  actual[function.open + 1] == "return" else { return nil }
            redacted.replaceSubrange((function.open + 2)..<close,
                with: ["__uncheckedPredicateLeaf\(index)__"])
        }
        return (source, redacted)
    }
    func canonicalPredicateNames(_ tokens: [String]) -> [String] {
        let declared = Set(tokens.indices.compactMap { index -> String? in
            guard index > 0, tokens[index - 1] == "func",
                  ["_predicate", "_membershipPredicate"].contains(where: {
                      tokens[index].hasPrefix($0) && Int(tokens[index].dropFirst($0.count)) != nil
                  }) else { return nil }
            return tokens[index]
        })
        var names: [String: String] = [:]
        var normalized: [String] = []
        normalized.reserveCapacity(tokens.count)
        for (index, token) in tokens.enumerated() {
            let declaration = index > 0 && tokens[index - 1] == "func"
            let call = index + 1 < tokens.count && tokens[index + 1] == "(" &&
                (index == 0 || tokens[index - 1] != ".")
            guard declared.contains(token), declaration || call else {
                normalized.append(token)
                continue
            }
            if let name = names[token] {
                normalized.append(name)
            } else {
                let name = "_predicate\(names.count)"
                names[token] = name
                normalized.append(name)
            }
        }
        return normalized
    }
    func domainRangeEqualitySource(_ root: CompiledExpression, parameters: [String]) -> String? {
        guard root.operation == .equal, root.resultType == .bool, root.children.count == 2 else { return nil }
        let domainFirst = root.children[0].operation == .domain && root.children[1].operation == .integerRange
        let rangeFirst = root.children[0].operation == .integerRange && root.children[1].operation == .domain
        guard domainFirst || rangeFirst else { return nil }
        let domain = root.children[domainFirst ? 0 : 1], range = root.children[domainFirst ? 1 : 0]
        // shortcut: dictionary state reads only; extend with independent function-child output rules.
        guard domain.children.count == 1, range.children.count == 2,
              domain.resultType == .set(.int), range.resultType == .set(.int),
              case .dictionary(.int, _) = domain.children[0].resultType,
              case .stateVariable(let id) = domain.children[0].operation,
              domain.children[0].children.isEmpty,
              program.variableTypes[id] == domain.children[0].resultType,
              let field = stateFields[id],
              let lower = directScalarTokens(range.children[0], parameters: parameters)
                ?? arithmeticIntTokens(range.children[0], parameters: parameters),
              let upper = directScalarTokens(range.children[1], parameters: parameters)
                ?? arithmeticIntTokens(range.children[1], parameters: parameters) else { return nil }
        let function = "let _domainFunction = state.state.\(field)"
        let bounds = "let _domainBounds = (\(lower.joined(separator: " ")), \(upper.joined(separator: " ")))"
        let bindings = domainFirst ? [function, bounds] : [bounds, function]
        return """
        (try { () throws -> \(nativeBoolType) in
            \(bindings.joined(separator: "\n"))
            guard !_domainFunction.isEmpty else { return _domainBounds.0 > _domainBounds.1 }
            let _domainLast = _domainBounds.0.addingReportingOverflow(_domainFunction.count - 1)
            return !_domainLast.overflow && _domainLast.partialValue == _domainBounds.1
                && _domainFunction.keys.allSatisfy { _domainBounds.0 <= $0 && $0 <= _domainBounds.1 }
        }())
        """
    }
    func checkedValueTokens(
        _ expression: CompiledExpression, parameters: [String], actual: [String]
    ) -> (expected: [String], actual: [String])? {
        func tokens(_ source: String) -> [String] {
            Parser.parse(source: source).tokens(viewMode: .sourceAccurate)
                .map(\.text).filter { !$0.isEmpty }
        }
        if let source = domainRangeEqualitySource(expression, parameters: parameters) {
            return (tokens(source), actual)
        }
        if case .controlLocation(let id) = expression.operation,
           expression.resultType == .controlLocation, expression.children.isEmpty,
           program.layout.controlLocations.contains(where: { $0.id == id }) {
            return (tokens("_ControlLocation.location\(id.ordinal)"), actual)
        }
        if case .value(.set(let members)) = expression.operation,
           case .set(let element) = expression.resultType,
           expression.children.isEmpty, element == .int || element == .bool {
            let values = members.sorted().compactMap { member -> String? in
                switch (member, element) {
                case (.integer(let value), .int):
                    return value == Int.min ? "\(nativeIntType).min" : String(value)
                case (.boolean(let value), .bool):
                    return value ? "true" : "false"
                default:
                    return nil
                }
            }
            guard values.count == members.count else { return nil }
            let type = element == .int ? nativeIntType : nativeBoolType
            return (tokens("Set<\(type)>([\(values.joined(separator: ", "))])"), actual)
        }
        func checkedSequenceSource(_ node: CompiledExpression) -> String? {
            guard case .array(let element) = node.resultType,
                  element == .int || element == .bool else { return nil }
            let typeName = element == .int ? nativeIntType : nativeBoolType
            switch node.operation {
            case .stateVariable(let variable):
                return stateFields[variable].map { "state.state.\($0)" }
            case .boundValue(let binding) where program.bindingTypes[binding] == node.resultType:
                guard let name = program.binderNames[binding].map({ "_\($0)_\(binding.ordinal)" }),
                      parameters.contains(name) else { return nil }
                return name
            case .tuplePrefix:
                guard node.children.count == 2,
                      node.children[0].resultType == node.resultType,
                      node.children[1].resultType == .int,
                      let sequence = checkedSequenceSource(node.children[0]),
                      let length = directScalarTokens(node.children[1], parameters: parameters)
                        ?? arithmeticIntTokens(node.children[1], parameters: parameters) else { return nil }
                return """
                (try { () throws -> [\(typeName)] in
                    let _sequenceValue = \(sequence)
                    let _prefixLength = \(length.joined(separator: " "))
                    return try SwiftTLA._NativeMachineOperations.sequencePrefix(_sequenceValue, length: _prefixLength)
                }())
                """
            case .tupleRemoving:
                guard node.children.count == 2,
                      node.children[0].resultType == node.resultType,
                      node.children[1].resultType == .int,
                      let sequence = checkedSequenceSource(node.children[0]),
                      let index = directScalarTokens(node.children[1], parameters: parameters)
                        ?? arithmeticIntTokens(node.children[1], parameters: parameters) else { return nil }
                return """
                (try { () throws -> [\(typeName)] in
                    let _sequenceValue = \(sequence)
                    let _sequenceIndex = \(index.joined(separator: " "))
                    return try SwiftTLA._NativeMachineOperations.sequenceRemoving(_sequenceValue, at: _sequenceIndex)
                }())
                """
            case .tupleConcatenate:
                guard node.children.count == 2,
                      node.children.allSatisfy({ $0.resultType == node.resultType }),
                      let left = checkedSequenceSource(node.children[0]),
                      let right = checkedSequenceSource(node.children[1]) else { return nil }
                return """
                (try { () throws -> [\(typeName)] in
                    let _leftValue: [\(typeName)] = \(left)
                    let _rightValue: [\(typeName)] = \(right)
                    let _rightElements = _rightValue
                    let _leftElements = _leftValue
                    return SwiftTLA._NativeMachineOperations.sequenceConcatenate(_leftElements, _rightElements)
                }())
                """
            case .tupleAppend:
                guard node.children.count == 2,
                      node.children[0].resultType == node.resultType,
                      node.children[1].resultType == element,
                      let sequence = checkedSequenceSource(node.children[0]),
                      let appended = directScalarTokens(node.children[1], parameters: parameters)
                        ?? arithmeticIntTokens(node.children[1], parameters: parameters)
                        ?? scalarPredicateTokens(node.children[1], parameters: parameters) else { return nil }
                return """
                (try { () throws -> [\(typeName)] in
                    let _sequenceValue: [\(typeName)] = \(sequence)
                    let _appendedValue: \(typeName) = \(appended.joined(separator: " "))
                    return SwiftTLA._NativeMachineOperations.sequenceAppend(_sequenceValue, _appendedValue)
                }())
                """
            default:
                return nil
            }
        }
        if (expression.operation == .tuplePrefix || expression.operation == .tupleRemoving ||
            expression.operation == .tupleConcatenate || expression.operation == .tupleAppend),
           let source = checkedSequenceSource(expression) {
            return (tokens(source), actual)
        }
        if expression.operation == .tupleLength,
           expression.children.count == 1,
           let sequence = checkedSequenceSource(expression.children[0]) {
            return (tokens("(\(sequence).count)"), actual)
        }
        if expression.operation == .tupleHead,
           expression.children.count == 1,
           let sequence = checkedSequenceSource(expression.children[0]) {
            return (tokens("(try SwiftTLA._NativeMachineOperations.sequenceHead(\(sequence)))"), actual)
        }
        if expression.operation == .tupleTail,
           expression.children.count == 1,
           let sequence = checkedSequenceSource(expression.children[0]) {
            return (tokens("(try SwiftTLA._NativeMachineOperations.sequenceTail(\(sequence)))"), actual)
        }
        if expression.operation == .tupleDynamicAccess,
           expression.children.count == 2,
           (expression.resultType == .int || expression.resultType == .bool),
           expression.children[1].resultType == .int,
           let sequence = checkedSequenceSource(expression.children[0]),
           let index = directScalarTokens(expression.children[1], parameters: parameters)
                ?? arithmeticIntTokens(expression.children[1], parameters: parameters) {
            let typeName = expression.resultType == .int ? nativeIntType : nativeBoolType
            let source = """
            (try { () throws -> \(typeName) in
                let _sequenceValue = \(sequence)
                let _sequenceIndex = \(index.joined(separator: " "))
                return try SwiftTLA._NativeMachineOperations.sequenceElement(_sequenceValue, at: _sequenceIndex)
            }())
            """
            return (tokens(source), actual)
        }
        if let tokens = scalarPredicateTokens(expression, parameters: parameters)
            ?? arithmeticIntTokens(expression, parameters: parameters)
            ?? directScalarTokens(expression, parameters: parameters) {
            return (tokens, actual)
        }
        guard let tree = checkedBooleanTree(expression, parameters: parameters, actual: actual) else {
            return nil
        }
        return (tokens(tree.source), tree.actual)
    }
    func firstTokenDifference(_ actual: [String], _ expected: [String]) -> String {
        let index = zip(actual, expected).enumerated().first { $0.element.0 != $0.element.1 }?.offset
            ?? min(actual.count, expected.count)
        let actualToken = index < actual.count ? actual[index] : "<end>"
        let expectedToken = index < expected.count ? expected[index] : "<end>"
        return "token \(index): expected \(expectedToken), actual \(actualToken) " +
            "(expected \(expected.count) tokens, actual \(actual.count))"
    }
    func requireParsedIntegerScalar(
        _ value: CompiledExpression, id: Int, parameters: [String], at path: String
    ) throws {
        guard value.resultType == .int,
              directScalarTokens(value, parameters: parameters) != nil ||
                arithmeticIntTokens(value, parameters: parameters) != nil else { return }
        guard let statement = firstStatements[id],
              statement.is(VariableDeclSyntax.self) || statement.is(IfExprSyntax.self),
              !statement.hasError else {
            throw invalid(path, "a parsed scalar statement without syntax recovery",
                firstStatements[id].map { "statement \($0.kind), parser errors \($0.hasError)" }
                    ?? "missing scalar statement")
        }
    }
    for guardNode in guards {
        guard let tokens = bodies[guardNode.id], let bindings = parameters[guardNode.id] else {
            throw invalid("native.action.guard.\(guardNode.id)",
                "a generated guard with its compiled bindings", "missing guard body or bindings")
        }
        let expected: [String]?
        var actualGuard = tokens
        if let constant = guardNode.predicate.booleanConstant {
            expected = constant ? ["try", "emit", "(", "updates", ")"] : ["return"]
        } else if let predicate = scalarPredicateTokens(guardNode.predicate, parameters: bindings) {
            expected = ["guard"] + predicate + ["else", "{", "return", "}",
                "try", "emit", "(", "updates", ")"]
        } else if let tree = checkedBooleanTree(guardNode.predicate,
            parameters: bindings, actual: tokens) {
            let declaration = Parser.parse(source: """
            func proof() {
                guard \(tree.source) else { return }
                try emit(updates)
            }
            """).statements.first?.item.as(FunctionDeclSyntax.self)
            expected = declaration?.body?.statements.tokens(viewMode: .sourceAccurate).map(\.text)
            actualGuard = tree.actual
        } else if booleanPredicateNodes(guardNode.predicate) != nil {
            throw invalid("native.action.guard.\(guardNode.id)",
                "a complete generated Boolean branch tree", "unreadable predicate functions")
        } else {
            // shortcut: opaque predicate values need an independent output link; retain the guard gate meanwhile.
            let suffix = ["else", "{", "return", "}", "try", "emit", "(", "updates", ")"]
            guard tokens.first == "guard", tokens.count > suffix.count + 1,
                  Array(tokens.suffix(suffix.count)) == suffix else {
                throw invalid("native.action.guard.\(guardNode.id)",
                    "one predicate gating exactly one unchanged update emission", "guard body \(tokens)")
            }
            expected = nil
        }
        if let expected, canonicalPredicateNames(actualGuard) != canonicalPredicateNames(expected) {
            throw invalid("native.action.guard.\(guardNode.id)",
                "the compiled predicate gates exactly one unchanged update emission", "guard body \(tokens)")
        }
    }
    for (id, child, value) in definitions {
        guard let tokens = bodies[id], tokens.count >= 3,
              tokens[0] == "let", tokens[2] == "=", tokens[1].hasPrefix("_") else {
            throw invalid("native.action.binding.\(id)",
                "a captured value before its child call", "missing or malformed binding")
        }
        let name = tokens[1]
        guard let parent = parameters[id], let childParameters = parameters[child],
              parent.suffix(2) == ["updates", "emit"] else {
            throw invalid("native.action.binding.\(id)",
                "current bindings, updates, and emitter parameters", "unexpected parameter list")
        }
        let arguments = Array(parent.dropLast(2)) + [name, "updates", "emit"]
        guard childParameters == arguments else {
            throw invalid("native.action.binding.\(id)",
                "the child receives every inherited binding and the captured value", "incorrect child parameters")
        }
        var expectedCall = ["try", "_actionPart\(child)", "("]
        for (index, argument) in arguments.enumerated() {
            if index > 0 { expectedCall.append(",") }
            expectedCall.append(argument)
        }
        expectedCall.append(")")
        guard tokens.suffix(expectedCall.count) == expectedCall else {
            throw invalid("native.action.binding.\(id)",
                "the child receives inherited and captured values unchanged", "generated child arguments differ")
        }
        let initializer = Array(tokens[3..<(tokens.count - expectedCall.count)])
        try requireParsedIntegerScalar(value, id: id, parameters: parent,
            at: "native.action.binding.\(id)")
        let checkedInitializer = checkedValueTokens(value, parameters: parent, actual: initializer)
        if checkedInitializer == nil, requireScalarLeaves || booleanPredicateNodes(value) != nil {
            throw invalid("native.action.binding.\(id)",
                "a complete generated scalar value or Boolean branch tree", "unreadable value expression")
        }
        if let checkedInitializer,
           canonicalPredicateNames(checkedInitializer.actual) !=
                canonicalPredicateNames(checkedInitializer.expected) {
            throw invalid("native.action.binding.\(id)",
                "the captured value reads its compiled source",
                firstTokenDifference(canonicalPredicateNames(checkedInitializer.actual),
                    canonicalPredicateNames(checkedInitializer.expected)))
        }
    }
    for id in conjunctions {
        guard let children = expectedChildren[id], children.count == 2,
              let parent = parameters[id], parent.suffix(2) == ["updates", "emit"],
              parameters[children[0]] == parent, parameters[children[1]] == parent else {
            throw invalid("native.action.conjunction.\(id)",
                "both children inherit the same bindings and update channels", "invalid child parameters")
        }
        let bindings = parent.dropLast(2)
        let prefix = bindings.isEmpty ? "" : bindings.joined(separator: ", ") + ", "
        let expected = Parser.parse(source: """
        func proof() {
            try _actionPart\(children[0])(\(prefix)updates, { candidate in
                try _actionPart\(children[1])(\(prefix)candidate, emit)
            })
        }
        """).statements.first?.item.as(FunctionDeclSyntax.self)
        let expectedBody = expected?.body?.statements.tokens(viewMode: .sourceAccurate).map(\.text) ?? []
        guard expected != nil, bodies[id] == expectedBody else {
            throw invalid("native.action.conjunction.\(id)",
                "pass every first-child update to the second child before emitting it",
                "generated conjunction differs from the checked rule")
        }
    }
    for id in alternatives {
        let tokens = bodies[id]!
        let positions = tokens.indices.filter { index in
            index > 0 && index + 1 < tokens.count && tokens[index].hasPrefix("_actionPart") &&
                tokens[index - 1] == "try" && tokens[index + 1] == "("
        }
        func call(at position: Int) -> [String]? {
            var depth = 0
            for end in (position + 1)..<tokens.count {
                if tokens[end] == "(" { depth += 1 }
                if tokens[end] == ")" { depth -= 1 }
                if depth == 0 { return Array(tokens[(position - 1)...end]) }
            }
            return nil
        }
        guard positions.count == 2,
              let right = call(at: positions[0]), let left = call(at: positions[1]),
              Array(right.dropFirst(2)) == Array(left.dropFirst(2)),
              Array(right.suffix(4)) == ["updates", ",", "branchEmit", ")"] else {
            throw invalid("native.action.alternative.\(id)",
                "both branches receive the same bindings, updates, and branch emitter", "invalid child calls")
        }
        let expected = ["try", "SwiftTLA", ".", "_NativeMachineOperations", ".", "visitAlternatives", "(",
                        "[", "false", ",", "true", "]", ",", "emit", ":", "emit", ")", "{",
                        "second", ",", "branchEmit", "in", "if", "second", "{"] + right +
            ["}", "else", "{"] + left + ["}", "}"]
        guard tokens == expected else {
            throw invalid("native.action.alternative.\(id)",
                "the shared ordered alternative visitor with both compiled branches",
                "generated alternative body differs from the checked rule")
        }
    }
    guard conditions.count == conditionals.count,
          Set(conditions.map(\.id)).count == conditions.count,
          Set(conditions.map(\.id)) == Set(conditionals) else {
        throw invalid("native.action.condition", "one condition per compiled conditional",
            "found \(conditions.count) conditions for \(conditionals.count) conditional nodes")
    }
    for condition in conditions {
        let id = condition.id
        let tokens = bodies[id]!
        let children = expectedChildren[id]!
        let positions = tokens.indices.filter { index in
            index > 0 && index + 1 < tokens.count && tokens[index].hasPrefix("_actionPart") &&
                tokens[index - 1] == "try" && tokens[index + 1] == "("
        }
        func call(at position: Int) -> [String]? {
            var depth = 0
            for end in (position + 1)..<tokens.count {
                if tokens[end] == "(" { depth += 1 }
                if tokens[end] == ")" { depth -= 1 }
                if depth == 0 { return Array(tokens[(position - 1)...end]) }
            }
            return nil
        }
        guard positions.count == 2, let yes = call(at: positions[0]),
              let no = call(at: positions[1]),
              yes.count > 4, no.count > 4,
              yes[1] == "_actionPart\(children[0])", no[1] == "_actionPart\(children[1])",
              Array(yes.dropFirst(2)) == Array(no.dropFirst(2)),
              Array(yes.suffix(4)) == ["updates", ",", "emit", ")"] else {
            throw invalid("native.action.conditional.\(id)",
                "both selected branches receive the same bindings, updates, and emitter",
                "invalid conditional child calls")
        }
        let predicate = conditionalPredicates[id]!
        let bindings = parameters[id]!
        let checkedPredicate: String
        var actualConditional = tokens
        if let scalar = scalarPredicateTokens(predicate, parameters: bindings) {
            checkedPredicate = scalar.joined(separator: " ")
        } else if let tree = checkedBooleanTree(predicate, parameters: bindings, actual: tokens) {
            checkedPredicate = tree.source
            actualConditional = tree.actual
        } else if booleanPredicateNodes(predicate) != nil {
            throw invalid("native.action.conditional.\(id)",
                "a complete generated Boolean branch tree", "unreadable predicate functions")
        } else {
            checkedPredicate = condition.value
        }
        let expected = Parser.parse(source: """
        func proof() {
            try SwiftTLA._NativeMachineOperations.visitConditional({ \(checkedPredicate) },
                ifTrue: { \(yes.joined(separator: " ")) },
                ifFalse: { \(no.joined(separator: " ")) })
        }
        """).statements.first?.item.as(FunctionDeclSyntax.self)
        let expectedBody = expected?.body?.statements.tokens(viewMode: .sourceAccurate).map(\.text) ?? []
        guard canonicalPredicateNames(actualConditional) == canonicalPredicateNames(expectedBody) else {
            throw invalid("native.action.conditional.\(id)",
                "the compiled condition selects exactly its corresponding child",
                "generated conditional body differs from the checked rule")
        }
    }
    guard parts.count == expectedWriteCount,
          Set(parts.map(\.id)) == Set(assignments.keys).union(frames.keys) else {
        throw CompilationDiagnostic(
            code: .unsupportedGeneratedValueShape, stage: .validation,
            path: "native.action.write", expected: "one unique generated write per compiled assignment or frame",
            actual: "found \(parts.count) write parts for \(expectedWriteCount) compiled writes",
            nextSafeAction: "Report this native code generation failure."
        )
    }
    for part in parts {
        if let variable = frames[part.id] {
            guard let slot = slotName(variable), part.slot == slot,
                  part.value == (stateFields[variable].map { "state.state.\($0)" } ?? "state.\(slot)") else {
                throw invalid("native.action.write.\(part.id)",
                    "the compiled frame variable and its prior-state value",
                    "a different generated frame write")
            }
        }
        let name = "_actionPart\(part.id)"
        let expected = Parser.parse(source: """
        func proof() {
            if let merged = updates.merging(_Updates(\(part.slot): \(part.value))) { try emit(merged) }
        }
        """).statements.first?.item.as(FunctionDeclSyntax.self)
        let actualBody = bodies[part.id] ?? []
        let expectedBody: [String] = if let statements = expected?.body?.statements {
            Array(statements.tokens(viewMode: .sourceAccurate)).map(\.text)
        } else { [] }
        guard expected != nil, actualBody == expectedBody else {
            throw CompilationDiagnostic(
                code: .unsupportedGeneratedValueShape, stage: .validation,
                path: "native.action.write.\(part.id)",
                expected: "merge the compiled write to \(part.slot) and emit only a compatible update",
                actual: "\(name): \(actualBody.prefix(40))",
                nextSafeAction: "Report this native code generation failure."
            )
        }
        if let assignment = assignments[part.id], let bindings = parameters[part.id] {
            guard part.slot == slotName(assignment.variable) else {
                throw invalid("native.action.write.\(part.id)",
                    "the compiled assignment target", "a different generated state slot")
            }
            try requireParsedIntegerScalar(assignment.value, id: part.id, parameters: bindings,
                at: "native.action.write.\(part.id)")
            let checkedValue = checkedValueTokens(assignment.value, parameters: bindings, actual: actualBody)
            let controlLiteral: Bool = if case .controlLocation = assignment.value.operation { true } else { false }
            let scalarSetLiteral: Bool = if case .value(.set) = assignment.value.operation,
                case .set(let element) = assignment.value.resultType {
                element == .int || element == .bool
            } else { false }
            if checkedValue == nil, requireScalarLeaves || controlLiteral ||
                scalarSetLiteral || booleanPredicateNodes(assignment.value) != nil {
                throw invalid("native.action.write.\(part.id)",
                    "a complete generated scalar value or Boolean branch tree", "unreadable value expression")
            }
            guard let checkedValue else { continue }
            let compiled = Parser.parse(source: """
            func proof() {
                if let merged = updates.merging(_Updates(\(part.slot): \(checkedValue.expected.joined(separator: " ")))) { try emit(merged) }
            }
            """).statements.first?.item.as(FunctionDeclSyntax.self)
            let compiledBody = compiled?.body?.statements.tokens(viewMode: .sourceAccurate).map(\.text) ?? []
            guard compiled != nil,
                  canonicalPredicateNames(checkedValue.actual) == canonicalPredicateNames(compiledBody) else {
                throw invalid("native.action.write.\(part.id)",
                    "the assigned value evaluates its compiled scalar expression",
                    "\(name): \(actualBody.prefix(40))")
            }
        }
    }
}

func nativeDeclarations(_ source: String) throws -> [DeclSyntax] {
    let parsed = Parser.parse(source: source)
    return try parsed.statements.map { statement in
        guard let declaration = statement.item.as(DeclSyntax.self) else {
            throw CompilationDiagnostic(
                code: .unsupportedGeneratedValueShape, stage: .validation,
                path: "native.declaration", expected: "a generated Swift declaration",
                actual: statement.description,
                nextSafeAction: "Report this native code generation failure."
            )
        }
        return declaration
    }
}
