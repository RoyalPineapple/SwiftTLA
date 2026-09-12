import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftParser
import SwiftTLA

extension NativeSwiftEmitter {
    mutating func machineMembers() throws -> [DeclSyntax] {
        let surface = model.surface
        let collections = surface.collections
        let collectionParameters = collections.map { "\($0.swiftIdentifier) \($0.membersIdentifier): [\($0.elementType).ID]" }.joined(separator: ", ")
        let collectionArguments = collections.map { "\($0.swiftIdentifier): \($0.membersIdentifier)" }.joined(separator: ", ")
        let appendedParameters = collectionParameters.isEmpty ? "" : ", \(collectionParameters)"
        let appendedArguments = collectionArguments.isEmpty ? "" : ", \(collectionArguments)"
        var declarations: [DeclSyntax] = []
        let fields = try program.layout.variables.filter { stateMemberNames[$0.id] == nil }.map { variable in
            "let \(self.variable(variable.id)): \(try swiftType(program.variableTypes[variable.id]!))"
        }.joined(separator: "\n")
        declarations += try nativeDeclarations("""
        public struct Snapshot: Hashable, Sendable {
            public let state: State
            \(fields)
        }
        private var _execution: Snapshot
        """)
        for collection in collections {
            declarations.append(DeclSyntax(stringLiteral: "private let \(collection.membersIdentifier): [\(collection.elementType).ID]"))
        }
        declarations += try nativeDeclarations("""
        private init(execution: Snapshot\(appendedParameters)) {
            _execution = execution
            \(collections.map { "self.\($0.membersIdentifier) = \($0.membersIdentifier)" }.joined(separator: "\n"))
        }
        """)
        let stateFields = try surface.variables.map { variable in
            "public let \(variable.swiftIdentifier): \(try swiftType(program.variableTypes[variable.id]!))"
        }.joined(separator: "\n")
        let stateParameters = try surface.variables.map { variable in
            "\(variable.swiftIdentifier) _value\(variable.id.ordinal): \(try swiftType(program.variableTypes[variable.id]!))"
        }.joined(separator: ", ")
        let stateAssignments = surface.variables.map { "self.\($0.swiftIdentifier) = _value\($0.id.ordinal)" }.joined(separator: "\n")
        declarations += try nativeDeclarations("""
        public struct State: Hashable, Sendable {
            \(stateFields)
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
        declarations += try actionDeclarations()
        declarations += try updateDeclarations()
        declarations += try collectionValidationDeclarations(parameters: appendedParameters)
        declarations += try initialDeclarations(parameters: collectionParameters, arguments: collectionArguments)
        let terminalActions = program.layout.actions.filter { $0.declaration.name == CompilerControlSymbol.terminatingAction.rawValue }
        let emittedActionIDs = Set(surface.actions.map(\.compiledAction)).union(enabledActionIDs).union(terminalActions.map(\.id))
        declarations += try program.behavior.actions.filter { emittedActionIDs.contains($0.id) }.map {
            try updateFunction($0, collectionParameters: appendedParameters)
        }
        declarations += try enabledDeclarations(collectionParameters: appendedParameters, collectionArguments: appendedArguments)
        let actionFunctions = try surface.actions.map { surfaceAction in
            let action = program[surfaceAction.compiledAction]
            return try successorFunction(action, surface: surfaceAction, collectionParameters: appendedParameters, collectionArguments: appendedArguments)
        }
        declarations += actionFunctions
        declarations += try dispatchDeclarations(collectionArguments: appendedArguments)
        declarations += try propertyDeclarations(collectionParameters: appendedParameters)
        declarations += actorMembers()
        if !program.layout.controlLocations.isEmpty {
            declarations += try nativeDeclarations("""
            @_documentation(visibility: internal)
            public enum _ControlLocation: Int, Hashable, Sendable {
                \(program.layout.controlLocations.map { "case location\($0.id.ordinal) = \($0.id.ordinal)" }.joined(separator: "\n"))
            }
            """)
        }
        let atoms = typeDeclarations.atoms
        if !atoms.isEmpty {
            declarations += try nativeDeclarations("""
            @_documentation(visibility: internal)
            public enum _Atom: String, Hashable, Sendable {
                \(atoms.enumerated().map { "case atom\($0.offset) = \(String(reflecting: $0.element))" }.joined(separator: "\n"))
            }
            """)
        }
        for (index, alternatives) in typeDeclarations.unions.enumerated() {
            let cases = try alternatives.enumerated().map {
                "case alternative\($0.offset + 1)(\(try swiftType($0.element)))"
            }.joined(separator: "\n")
            declarations += try nativeDeclarations("""
            public enum NativeUnion\(index): Hashable, Sendable {
                \(cases)
            }
            """)
        }
        for (index, type) in typeDeclarations.records.enumerated() {
            let elements: [CompiledValueType]
            switch type {
            case .tuple(let items): elements = items
            case .record(let fields): elements = fields.map(\.type)
            default: throw unsupported("record declaration")
            }
            let fields = try elements.enumerated().map { "public let \(fieldName(type, index: $0.offset)): \(try swiftType($0.element))" }.joined(separator: "\n")
            let parameters = try elements.enumerated().map { "\(fieldName(type, index: $0.offset)) _field\($0.offset): \(try swiftType($0.element))" }.joined(separator: ", ")
            let assignments = elements.indices.map { "self.\(fieldName(type, index: $0)) = _field\($0)" }.joined(separator: "\n")
            declarations += try nativeDeclarations("""
            public struct NativeRecord\(index): Hashable, Sendable {
                \(fields)
                public init(\(parameters)) { \(assignments) }
            }
            """)
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
        let cases = try model.surface.actions.map { surface in
            let action = program[surface.compiledAction]
            guard action.bindings.count == surface.bindings.count else {
                throw unsupported("action binding layout")
            }
            if let collection = surface.collection {
                guard action.bindings.count == 1 else { throw unsupported("collection action binding layout") }
                return "case \(surface.swiftIdentifier)(member: \(collection.elementType).ID)"
            }
            let parameters = try zip(action.bindings, surface.bindings).filter { $0.1.isPublic }.map { binding, surfaceBinding in
                "\(surfaceBinding.swiftIdentifier): \(try swiftType(program.bindingTypes[binding.binder]!))"
            }.joined(separator: ", ")
            return "case \(surface.swiftIdentifier)" + (parameters.isEmpty ? "" : "(\(parameters))")
        }.joined(separator: "\n")
        return try nativeDeclarations("""
        public enum Action: Hashable, Sendable {
            \(cases)
        }
        """)
    }

    func collectionValidationDeclarations(parameters: String) throws -> [DeclSyntax] {
        let checks = model.surface.variables.compactMap { variable -> String? in
            guard let collection = variable.collection else { return nil }
            return """
            guard Set(\(stateValue(variable.id)).keys) == Set(\(collection.membersIdentifier)) else {
                throw GeneratedMachineStateDiagnostic.typeMismatch(
                    path: \(String(reflecting: collection.formalName)),
                    expected: "exactly the application IDs bound when the machine was created",
                    actual: String(describing: Array(\(stateValue(variable.id)).keys))
                )
            }
            """
        }.joined(separator: "\n")
        return try nativeDeclarations("""
        private static func _validateCollections(_ state: Snapshot\(parameters)) throws {
            \(checks)
        }
        """)
    }

    private func executionState(values: (VariableID) -> String) -> String {
        let publicFields = model.surface.variables.map {
            "\($0.swiftIdentifier): \(values($0.id))"
        }.joined(separator: ", ")
        let privateFields = program.layout.variables.filter { stateMemberNames[$0.id] == nil }.map {
            ", \(variable($0.id)): \(values($0.id))"
        }.joined()
        return "Snapshot(state: State(\(publicFields))\(privateFields))"
    }

    func updateDeclarations() throws -> [DeclSyntax] {
        let fields = try program.layout.variables.map { "var \(variable($0.id)): \(try swiftType(program.variableTypes[$0.id]!))? = nil" }.joined(separator: "\n")
        let merges = program.layout.variables.map { slot in
            let name = variable(slot.id)
            return """
            if let value = other.\(name) {
                if let previous = result.\(name), previous != value {
                    throw NativeMachineEvaluationError.conflictingAssignment(variable: \(String(reflecting: slot.declaration.name)))
                }
                result.\(name) = value
            }
            """
        }.joined(separator: "\n")
        let updated = executionState { "\(variable($0)) ?? \(stateValue($0))" }
        return try nativeDeclarations("""
        private struct _Updates: Sendable {
            \(fields)
            func merging(_ other: Self) throws -> Self {
                var result = self
                \(merges)
                return result
            }
            func applying(to state: Snapshot) -> Snapshot {
                \(updated)
            }
        }
        """)
    }

    mutating func initialDeclarations(parameters: String, arguments: String) throws -> [DeclSyntax] {
        var code = "var result: [Snapshot] = []\n"
        var closing = ""
        for initialization in program.behavior.initializations {
            let type = program.variableTypes[initialization.variable]!
            let name = variable(initialization.variable)
            switch initialization.initialization {
            case .value(let expression):
                code += "let \(name): \(try swiftType(type)) = \(try self.expression(expression, state: ""))\n"
            case .memberOf(let expression):
                code += "for \(name) in \(try self.expression(expression, state: "")).sorted(by: \(try ordering(type))) {\n"
                closing += "}\n"
            }
        }
        code += "result.append(\(executionState(values: variable)))\n" + closing
        let validationArguments = arguments.isEmpty ? "" : ", " + arguments
        code += "for state in result { try _validateCollections(state\(validationArguments)) }\nreturn result"
        let appendedParameters = parameters.isEmpty ? "" : ", " + parameters
        let appendedArguments = arguments.isEmpty ? "" : ", " + arguments
        let validation = model.surface.collections.map { collection in
            """
            guard \(collection.membersIdentifier).count == \(collection.members.count), Set(\(collection.membersIdentifier)).count == \(collection.members.count) else {
                throw GeneratedMachineStateDiagnostic.typeMismatch(
                    path: \(String(reflecting: collection.formalName)),
                    expected: "\(collection.members.count) unique application IDs",
                    actual: String(describing: \(collection.membersIdentifier))
                )
            }
            """
        }.joined(separator: "\n")
        return try nativeDeclarations("""
        private static func _initialStates(\(parameters)) throws -> [Snapshot] {
            \(validation)
            \(code)
        }
        public static func initialMachines(\(parameters)) throws -> [Self] {
            try _initialStates(\(arguments)).map { Self(execution: $0\(appendedArguments)) }
        }
        public static func makeMachine(\(parameters)) throws -> Self {
            var candidates = try _initialStates(\(arguments))[...]
            guard let execution = candidates.popFirst() else { throw GeneratedMachineError.noInitialState }
            guard candidates.isEmpty else { throw GeneratedMachineError.ambiguousInitialState }
            return Self(execution: execution\(appendedArguments))
        }
        public static func makeMachine(_ initial: State\(appendedParameters)) throws -> Self {
            var candidates = try _initialStates(\(arguments)).filter { $0.state == initial }[...]
            guard let execution = candidates.popFirst() else { throw GeneratedMachineError.invalidInitialState }
            guard candidates.isEmpty else { throw GeneratedMachineError.ambiguousInitialState }
            return Self(execution: execution\(appendedArguments))
        }
        """)
    }

    mutating func actionFunctions(_ root: CompiledActionExpr) throws -> String {
        var pending: [(node: CompiledActionExpr, id: Int, bindings: [BinderID])] = [(root, 0, [])]
        var nextID = 1
        var declarations: [String] = []
        while let (node, id, bindings) = pending.popLast() {
            func childCall(_ child: CompiledActionExpr, binding: BinderID? = nil) -> String {
                let childBindings = bindings + (binding.map { [$0] } ?? [])
                let childID = nextID
                nextID += 1
                pending.append((child, childID, childBindings))
                return "try _actionPart\(childID)(\(childBindings.map(binder).joined(separator: ", ")))"
            }
            let body: String
            switch node {
            case .assign(let variableID, let value):
                body = "return [_Updates(\(variable(variableID)): \(try expression(value)))]"
            case .unchanged(let variableID):
                body = "return [_Updates(\(variable(variableID)): \(stateValue(variableID)))]"
            case .guard_(let predicate):
                if let constant = predicate.booleanConstant {
                    body = constant ? "return [_Updates()]" : "return []"
                } else {
                    body = "guard \(try expression(predicate)) else { return [] }\nreturn [_Updates()]"
                }
            case .existsAction(let binding, let domainExpression, let child):
                let element = program.bindingTypes[binding]!
                let domain = try expression(domainExpression)
                body = """
                return try \(domain).sorted(by: \(try ordering(element))).flatMap { (\(binder(binding)): \(try swiftType(element))) throws -> [_Updates] in
                    return \(childCall(child, binding: binding))
                }
                """
            case .define(let binding, let value, let child):
                body = "let \(binder(binding)) = \(try expression(value))\nreturn \(childCall(child, binding: binding))"
            case .ifElse(let condition, let yes, let no):
                body = "if \(try expression(condition)) { return \(childCall(yes)) } else { return \(childCall(no)) }"
            case .and(let lhs, let rhs):
                body = """
                let left = \(childCall(lhs))
                guard !left.isEmpty else { return [] }
                let right = \(childCall(rhs))
                return try left.flatMap { first -> [_Updates] in try right.map { try first.merging($0) } }
                """
            case .or(let lhs, let rhs):
                body = "let left = \(childCall(lhs))\nlet right = \(childCall(rhs))\nreturn left + right"
            }
            let parameters = try bindings.map {
                "_ \(binder($0)): \(try swiftType(program.bindingTypes[$0]!))"
            }.joined(separator: ", ")
            declarations.append("""
            func _actionPart\(id)(\(parameters)) throws -> [_Updates] {
                \(body)
            }
            """)
        }
        return declarations.joined(separator: "\n") + "\nreturn try _actionPart0()"
    }

    mutating func updateFunction(_ action: CompiledAction, collectionParameters: String) throws -> DeclSyntax {
        let parameters = try action.bindings.map {
            "\(binder($0.binder)): \(try swiftType(program.bindingTypes[$0.binder]!))"
        }.joined(separator: ", ")
        return DeclSyntax(stringLiteral: """
        private static func _updates\(action.id.ordinal)(from state: Snapshot\(parameters.isEmpty ? "" : ", " + parameters)\(collectionParameters), enabled: Set<Int>) throws -> [_Updates] {
            \(try actionFunctions(action.body))
        }
        """)
    }

    private func enabledActionsCall(_ dependencies: Set<ActionID>, state: String, collectionArguments: String) -> String {
        guard !dependencies.isEmpty else { return "[]" }
        let identifiers = dependencies.map(\.ordinal).sorted().map(String.init).joined(separator: ", ")
        return "try Self._enabledActions(in: \(state)\(collectionArguments), required: [\(identifiers)])"
    }

    func enabledDeclarations(collectionParameters: String, collectionArguments: String) throws -> [DeclSyntax] {
        guard !enabledActionIDs.isEmpty else { return [] }
        var checks = ""
        for index in program.behavior.enabledActionIndices {
            let action = program.behavior.actions[index]
            guard enabledActionIDs.contains(action.id) else { continue }
            var loops = ""
            var closing = ""
            var arguments: [String] = []
            for binding in action.bindings {
                let name = binder(binding.binder)
                let domain = try binding.values.map { try literal($0, as: program.bindingTypes[binding.binder]!) }.joined(separator: ", ")
                loops += "for \(name) in [\(domain)] {\n"
                closing += "}\n"
                arguments.append("\(name): \(name)")
            }
            checks += "if required.contains(\(action.id.ordinal)) {\n" + loops + "if try !_updates\(action.id.ordinal)(from: state\(arguments.isEmpty ? "" : ", " + arguments.joined(separator: ", "))\(collectionArguments), enabled: result).isEmpty { result.insert(\(action.id.ordinal)) }\n" + closing + "}\n"
        }
        return try nativeDeclarations("""
        private static func _enabledActions(in state: Snapshot\(collectionParameters), required: Set<Int>) throws -> Set<Int> {
            \(checks.isEmpty ? "return []" : "var result: Set<Int> = []\n" + checks + "\nreturn result")
        }
        """)
    }

    func successorFunction(_ action: CompiledAction, surface: MachineSurfacePlan.Action, collectionParameters: String, collectionArguments: String) throws -> DeclSyntax {
        let parameters = try action.bindings.map { binding in
            "\(binder(binding.binder)): \(try swiftType(program.bindingTypes[binding.binder]!))"
        }.joined(separator: ", ")
        let arguments = action.bindings.map { "\(binder($0.binder)): \(binder($0.binder))" }.joined(separator: ", ")
        let filtering: String
        if let constraint = program.behavior.constraint {
            let dependencies = constraint.enabledActions
            let enabled = dependencies.isEmpty ? "" : "let enabled = \(enabledActionsCall(dependencies, state: "state", collectionArguments: collectionArguments))\n"
            let enabledArgument = dependencies.isEmpty ? "[]" : "enabled"
            filtering = "let candidates = try updates.map { $0.applying(to: state) }.filter { state in\n\(enabled)return try Self._constraintHolds(in: state\(collectionArguments), enabled: \(enabledArgument))\n}"
        } else {
            filtering = "let candidates = updates.map { $0.applying(to: state) }"
        }
        return DeclSyntax(stringLiteral: """
        private static func _successors\(action.id.ordinal)(from state: Snapshot\(parameters.isEmpty ? "" : ", " + parameters)\(collectionParameters), enabled: Set<Int>) throws -> [Snapshot] {
            let updates = try _updates\(action.id.ordinal)(from: state\(arguments.isEmpty ? "" : ", " + arguments)\(collectionArguments), enabled: enabled)
            \(filtering)
            return candidates.reduce(into: [Snapshot]()) { states, state in
                if !states.contains(state) { states.append(state) }
            }
        }
        """)
    }

    func dispatchDeclarations(collectionArguments: String) throws -> [DeclSyntax] {
        guard !model.surface.actions.isEmpty else {
            return try nativeDeclarations("""
            public func enabledActions() throws -> [Action] { [] }
            public func successors() throws -> [(action: Action, machine: Self)] { [] }
            """)
        }
        var cases: [String] = []
        var enumeration: [String] = []
        for surface in model.surface.actions {
            let action = program[surface.compiledAction]
            var pattern: [String] = []
            var invocation: [String] = []
            var validations: [String] = []
            var actionArguments: [String] = []
            var loops = ""
            var closing = ""
            for (binding, surfaceBinding) in zip(action.bindings, surface.bindings) {
                let name = binder(binding.binder)
                let type = program.bindingTypes[binding.binder]!
                let domain: String
                if let collection = surface.collection {
                    domain = collection.membersIdentifier
                    pattern.append("member: let \(name)")
                    actionArguments.append("member: \(name)")
                } else {
                    domain = "[\(try binding.values.map { try literal($0, as: type) }.joined(separator: ", "))]"
                    if surfaceBinding.isPublic {
                        pattern.append("\(surfaceBinding.swiftIdentifier): let \(name)")
                        actionArguments.append("\(surfaceBinding.swiftIdentifier): \(name)")
                    }
                }
                if surfaceBinding.isPublic || surface.collection != nil {
                    if let collection = surface.collection {
                        validations.append("""
                        guard \(domain).contains(\(name)) else {
                            throw GeneratedMachineStateDiagnostic.typeMismatch(
                                path: \(String(reflecting: collection.formalName + ".member")),
                                expected: "an application ID bound when the machine was created",
                                actual: String(describing: \(name))
                            )
                        }
                        """)
                    } else {
                        validations.append("guard \(domain).contains(\(name)) else { return [] }")
                    }
                    invocation.append("\(name): \(name)")
                    loops += "for \(name) in \(domain) {\n"
                    closing += "}\n"
                } else {
                    invocation.append("\(name): \(try literal(binding.values[0], as: type))")
                }
            }
            let label = ".\(surface.swiftIdentifier)" + (pattern.isEmpty ? "" : "(\(pattern.joined(separator: ", ")))")
            let enabled = enabledActionsCall(program.behavior.enabledActionDependencies[action.id] ?? [],
                state: "_execution", collectionArguments: collectionArguments)
            cases.append("""
            case \(label):
                \(validations.joined(separator: "\n"))
                return try Self._successors\(action.id.ordinal)(from: _execution\(invocation.isEmpty ? "" : ", " + invocation.joined(separator: ", "))\(collectionArguments), enabled: \(enabled))
            """)
            let actionValue = ".\(surface.swiftIdentifier)" + (actionArguments.isEmpty ? "" : "(\(actionArguments.joined(separator: ", ")))")
            enumeration.append("do {\n" + loops + "result.append(\(actionValue))\n" + closing + "}\n")
        }
        return try nativeDeclarations("""
        private func _successors(for action: Action) throws -> [Snapshot] {
            switch action {
                \(cases.joined(separator: "\n"))
            }
        }
        public func isEnabled(_ action: Action) throws -> Bool {
            try !_successors(for: action).isEmpty
        }
        public func successors(for action: Action) throws -> [Self] {
            try _successors(for: action).map { execution in
                try Self._validateCollections(execution\(collectionArguments))
                return Self(execution: execution\(collectionArguments))
            }
        }
        private var _actions: [Action] {
            var result: [Action] = []
            \(enumeration.joined(separator: "\n"))
            return result
        }
        public func successors() throws -> [(action: Action, machine: Self)] {
            try _actions.flatMap { action in
                try successors(for: action).map { (action, $0) }
            }
        }
        public func enabledActions() throws -> [Action] {
            try _actions.filter { try isEnabled($0) }
        }
        public mutating func send(_ action: Action) throws -> Transition {
            var candidates = try _successors(for: action)[...]
            guard let next = candidates.popFirst() else { throw GeneratedMachineError.noMatchingSuccessor }
            guard candidates.isEmpty else { throw GeneratedMachineError.ambiguousAction }
            try Self._validateCollections(next\(collectionArguments))
            let before = state
            _execution = next
            return Transition(action: action, before: before, after: state)
        }
        """)
    }

    mutating func propertyDeclarations(collectionParameters: String) throws -> [DeclSyntax] {
        let arguments = model.surface.collections.map { ", \($0.swiftIdentifier): \($0.membersIdentifier)" }.joined()
        var declarations: [DeclSyntax] = []
        var checks: [String] = []
        declarations += try nativeDeclarations("public static var checksDeadlock: Bool { \(program.behavior.checkDeadlock) }")
        if let terminal = program.layout.actions.first(where: { $0.declaration.name == CompilerControlSymbol.terminatingAction.rawValue }) {
            declarations += try nativeDeclarations("""
            public func isTerminated() throws -> Bool {
                try !Self._updates\(terminal.id.ordinal)(from: _execution\(arguments), enabled: []).isEmpty
            }
            """)
        } else {
            declarations += try nativeDeclarations("public func isTerminated() throws -> Bool { false }")
        }
        if let constraint = program.behavior.constraint {
            declarations += try nativeDeclarations("""
            private static func _constraintHolds(in state: Snapshot\(collectionParameters), enabled: Set<Int>) throws -> Bool {
                \(try expression(constraint.expression))
            }
            """)
        }
        for invariant in program.behavior.invariants {
            declarations += try nativeDeclarations("""
            private static func _invariant\(invariant.id.ordinal)(in state: Snapshot\(collectionParameters), enabled: Set<Int>) throws -> Bool {
                \(try expression(invariant.predicate.expression))
            }
            """)
            let enabled = enabledActionsCall(invariant.predicate.enabledActions, state: "_execution", collectionArguments: arguments)
            checks.append("if try !Self._invariant\(invariant.id.ordinal)(in: _execution\(arguments), enabled: \(enabled)) { result.append(\(String(reflecting: invariant.name))) }")
        }
        declarations += try nativeDeclarations("""
        public func violatedInvariants() throws -> [String] {
            \(checks.isEmpty ? "return []" : "var result: [String] = []\n" + checks.joined(separator: "\n") + "\nreturn result")
        }
        """)
        if let assume = program.behavior.assume {
            declarations += try nativeDeclarations("""
            private static func _assumptionsHold(in state: Snapshot\(collectionParameters), enabled: Set<Int>) throws -> Bool {
                \(try expression(assume.expression))
            }
            public func assumptionsHold() throws -> Bool {
                try Self._assumptionsHold(in: _execution\(arguments), enabled: [])
            }
            """)
        } else {
            declarations += try nativeDeclarations("public func assumptionsHold() throws -> Bool { true }")
        }
        return declarations
    }

}

private func nativeDeclarations(_ source: String) throws -> [DeclSyntax] {
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
