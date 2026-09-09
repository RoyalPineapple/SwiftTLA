import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftParser
import SwiftTLA

extension NativeSwiftEmitter {
    mutating func machineMembers() throws -> [DeclSyntax] {
        let surface = model.compilation.machineSurfacePlan
        let collections = surface.collections
        let collectionParameters = collections.map { "\($0.swiftIdentifier) \(nativeCollectionBinding($0, in: model)): [\($0.elementType).ID]" }.joined(separator: ", ")
        let collectionArguments = collections.map { "\($0.swiftIdentifier): \(nativeCollectionBinding($0, in: model))" }.joined(separator: ", ")
        let appendedParameters = collectionParameters.isEmpty ? "" : ", \(collectionParameters)"
        let appendedArguments = collectionArguments.isEmpty ? "" : ", \(collectionArguments)"
        var declarations: [DeclSyntax] = []
        let fields = try compilation.layout.variables.map { variable in
            "var \(self.variable(variable.id)): \(try swiftType(program.variableTypes[variable.id]!))"
        }.joined(separator: "\n")
        declarations += try nativeDeclarations("""
        private struct _ExecutionState: Equatable, Sendable {
            \(fields)
        }
        private var _execution: _ExecutionState
        """)
        for collection in collections {
            declarations.append(DeclSyntax(stringLiteral: "private let \(nativeCollectionBinding(collection, in: model)): [\(collection.elementType).ID]"))
        }
        declarations += try nativeDeclarations("""
        private init(execution: _ExecutionState\(appendedParameters)) {
            _execution = execution
            \(collections.map { "self.\(nativeCollectionBinding($0, in: model)) = \(nativeCollectionBinding($0, in: model))" }.joined(separator: "\n"))
        }
        """)
        let stateFields = try surface.variables.map { variable in
            "public let \(variable.swiftIdentifier): \(try swiftType(program.variableTypes[compilation.layout.variables[variable.storageOrdinal].id]!))"
        }.joined(separator: "\n")
        let stateParameters = try surface.variables.map { variable in
            "\(variable.swiftIdentifier) _value\(variable.storageOrdinal): \(try swiftType(program.variableTypes[compilation.layout.variables[variable.storageOrdinal].id]!))"
        }.joined(separator: ", ")
        let stateAssignments = surface.variables.map { "self.\($0.swiftIdentifier) = _value\($0.storageOrdinal)" }.joined(separator: "\n")
        let stateArguments = surface.variables.map { "\($0.swiftIdentifier): execution.\(variable(compilation.layout.variables[$0.storageOrdinal].id))" }.joined(separator: ", ")
        declarations += try nativeDeclarations("""
        public struct State: Equatable, Sendable {
            \(stateFields)
            public init(\(stateParameters)) {
                \(stateAssignments)
            }
        }
        private static func _publicState(_ execution: _ExecutionState) -> State {
            State(\(stateArguments))
        }
        public var state: State { Self._publicState(_execution) }
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
        declarations += try compilation.semantics.actions.map { try rawActionFunction($0, collectionParameters: appendedParameters) }
        declarations += try enabledDeclarations(collectionParameters: appendedParameters, collectionArguments: appendedArguments)
        let actionFunctions = try surface.actions.map { surfaceAction in
            guard let action = compilation.semantics.actions.first(where: { $0.id == surfaceAction.compiledAction }) else {
                throw unsupported("missing resolved action")
            }
            return try successorFunction(action, surface: surfaceAction, collectionParameters: appendedParameters, collectionArguments: appendedArguments)
        }
        declarations += actionFunctions
        declarations += try dispatchDeclarations(collectionArguments: appendedArguments)
        declarations += try propertyDeclarations(collectionParameters: appendedParameters)
        declarations += MacroExpander.generateActorMembers(model: model)
        if !compilation.layout.controlLocations.isEmpty {
            declarations += try nativeDeclarations("""
            @_documentation(visibility: internal)
            public enum _ControlLocation: Int, Hashable, Sendable {
                \(compilation.layout.controlLocations.map { "case location\($0.id.ordinal) = \($0.id.ordinal)" }.joined(separator: "\n"))
            }
            """)
        }
        if !atoms.isEmpty {
            declarations += try nativeDeclarations("""
            @_documentation(visibility: internal)
            public enum _Atom: String, Hashable, Sendable {
                \(atoms.enumerated().map { "case atom\($0.offset) = \(String(reflecting: $0.element))" }.joined(separator: "\n"))
            }
            """)
        }
        // Register the complete generated type graph before emitting declarations.
        var recordCursor = 0
        var unionCursor = 0
        while recordCursor < records.count || unionCursor < unions.count {
            if recordCursor < records.count {
                let children: [NativeType]
                switch records[recordCursor] {
                case .record(let fields): children = fields.map(\.type)
                case .tuple(let values): children = values
                default: throw unsupported("record declaration")
                }
                for child in children { _ = try swiftType(child) }
                recordCursor += 1
            }
            if unionCursor < unions.count {
                for alternative in unions[unionCursor] { _ = try swiftType(alternative) }
                unionCursor += 1
            }
        }
        for (index, alternatives) in unions.enumerated() {
            let cases = try alternatives.enumerated().map {
                "case alternative\($0.offset + 1)(\(try swiftType($0.element)))"
            }.joined(separator: "\n")
            declarations += try nativeDeclarations("""
            public enum NativeUnion\(index): Hashable, Sendable {
                \(cases)
            }
            """)
        }
        // Emitting a record may discover nested records, so consume until complete.
        var index = 0
        while index < records.count {
            let type = records[index]
            let elements: [NativeType]
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
            index += 1
        }
        for (index, members) in finiteValues.enumerated() {
            declarations += try nativeDeclarations("""
            public enum NativeValue\(index): Hashable, Sendable {
                \(members.indices.map { "case \(finiteCaseName(members, index: $0))" }.joined(separator: "\n"))
            }
            """)
        }
        return declarations
    }

    mutating func actionDeclarations() throws -> [DeclSyntax] {
        let cases = try model.compilation.machineSurfacePlan.actions.map { surface in
            guard let action = compilation.semantics.actions.first(where: { $0.id == surface.compiledAction }),
                  action.bindings.count == surface.bindings.count else {
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

    mutating func collectionValidationDeclarations(parameters: String) throws -> [DeclSyntax] {
        let checks = model.compilation.machineSurfacePlan.variables.compactMap { variable -> String? in
            guard let collection = variable.collection else { return nil }
            return """
            guard Set(state.\(self.variable(compilation.layout.variables[variable.storageOrdinal].id)).keys) == Set(\(nativeCollectionBinding(collection, in: model))) else {
                throw GeneratedMachineStateDiagnostic.typeMismatch(
                    path: \(String(reflecting: collection.formalName)),
                    expected: "exactly the application IDs bound when the machine was created",
                    actual: String(describing: Array(state.\(self.variable(compilation.layout.variables[variable.storageOrdinal].id)).keys))
                )
            }
            """
        }.joined(separator: "\n")
        return try nativeDeclarations("""
        private static func _validateCollections(_ state: _ExecutionState\(parameters)) throws {
            \(checks)
        }
        """)
    }

    mutating func updateDeclarations() throws -> [DeclSyntax] {
        let fields = try compilation.layout.variables.map { "var \(variable($0.id)): \(try swiftType(program.variableTypes[$0.id]!))? = nil" }.joined(separator: "\n")
        let merges = compilation.layout.variables.map { slot in
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
        let arguments = compilation.layout.variables.map { "\(variable($0.id)): \(variable($0.id)) ?? state.\(variable($0.id))" }.joined(separator: ", ")
        return try nativeDeclarations("""
        private struct _Updates: Sendable {
            \(fields)
            func merging(_ other: Self) throws -> Self {
                var result = self
                \(merges)
                return result
            }
            func applying(to state: _ExecutionState) -> _ExecutionState {
                _ExecutionState(\(arguments))
            }
        }
        """)
    }

    mutating func initialDeclarations(parameters: String, arguments: String) throws -> [DeclSyntax] {
        var code = "var result: [_ExecutionState] = []\n"
        var closing = ""
        for initialization in compilation.semantics.variableInitializations {
            let type = program.variableTypes[initialization.variable]!
            let name = variable(initialization.variable)
            switch initialization.initialization {
            case .value, .expression:
                code += "let \(name): \(try swiftType(type)) = \(try expression(program.initializations[initialization.variable]!, state: ""))\n"
            case .memberOf:
                code += "for \(name) in \(try expression(program.initializations[initialization.variable]!, state: "")).sorted(by: \(try ordering(type))) {\n"
                closing += "}\n"
            }
        }
        let stateArguments = compilation.layout.variables.map { "\(variable($0.id)): \(variable($0.id))" }.joined(separator: ", ")
        code += "result.append(_ExecutionState(\(stateArguments)))\n" + closing
        let validationArguments = arguments.isEmpty ? "" : ", " + arguments
        code += "for state in result { try _validateCollections(state\(validationArguments)) }\nreturn result"
        let appendedParameters = parameters.isEmpty ? "" : ", " + parameters
        let appendedArguments = arguments.isEmpty ? "" : ", " + arguments
        let validation = model.compilation.machineSurfacePlan.collections.map { collection in
            """
            guard \(nativeCollectionBinding(collection, in: model)).count == \(collection.members.count), Set(\(nativeCollectionBinding(collection, in: model))).count == \(collection.members.count) else {
                throw GeneratedMachineStateDiagnostic.typeMismatch(
                    path: \(String(reflecting: collection.formalName)),
                    expected: "\(collection.members.count) unique application IDs",
                    actual: String(describing: \(nativeCollectionBinding(collection, in: model)))
                )
            }
            """
        }.joined(separator: "\n")
        return try nativeDeclarations("""
        private static func _initialStates(\(parameters)) throws -> [_ExecutionState] {
            \(validation)
            \(code)
        }
        public static func makeMachine(\(parameters)) throws -> Self {
            var candidates = try _initialStates(\(arguments))[...]
            guard let execution = candidates.popFirst() else { throw GeneratedMachineError.noInitialState }
            guard candidates.isEmpty else { throw GeneratedMachineError.ambiguousInitialState }
            return Self(execution: execution\(appendedArguments))
        }
        public static func makeMachine(_ initial: State\(appendedParameters)) throws -> Self {
            var candidates = try _initialStates(\(arguments)).filter { _publicState($0) == initial }[...]
            guard let execution = candidates.popFirst() else { throw GeneratedMachineError.invalidInitialState }
            guard candidates.isEmpty else { throw GeneratedMachineError.ambiguousInitialState }
            return Self(execution: execution\(appendedArguments))
        }
        """)
    }

    mutating func actionFunctions(_ root: NativeActionNodeID) throws -> String {
        var pending: [(id: NativeActionNodeID, bindings: [BinderID])] = [(root, [])]
        var declarations: [String] = []
        while let (id, bindings) = pending.popLast() {
            let node = program[id]
            var childBindings = bindings
            switch node.expression {
            case .define(let binding, _, _), .existsAction(let binding, _, _):
                childBindings.append(binding)
            default: break
            }
            pending.append(contentsOf: node.children.reversed().map { ($0, childBindings) })
            func childCall(_ index: Int) -> String {
                "try _actionPart\(node.children[index].ordinal)(\(childBindings.map(binder).joined(separator: ", ")))"
            }
            let body: String
            switch node.expression {
            case .assign(let variableID, _):
                body = "return [_Updates(\(variable(variableID)): \(try expression(node.expressions[0])))]"
            case .unchanged(let variableID):
                body = "return [_Updates(\(variable(variableID)): state.\(variable(variableID)))]"
            case .guard_:
                body = "guard \(try expression(node.expressions[0])) else { return [] }\nreturn [_Updates()]"
            case .existsAction(let binding, _, _):
                let element = node.bindings[binding]!
                let domain = try expression(node.expressions[0])
                body = """
                return try \(domain).sorted(by: \(try ordering(element))).flatMap { (\(binder(binding)): \(try swiftType(element))) throws -> [_Updates] in
                    return \(childCall(0))
                }
                """
            case .define(let binding, _, _):
                body = "let \(binder(binding)) = \(try expression(node.expressions[0]))\nreturn \(childCall(0))"
            case .ifElse:
                body = "if \(try expression(node.expressions[0])) { return \(childCall(0)) } else { return \(childCall(1)) }"
            case .and:
                body = """
                let left = \(childCall(0))
                guard !left.isEmpty else { return [] }
                let right = \(childCall(1))
                return try left.flatMap { first -> [_Updates] in try right.map { try first.merging($0) } }
                """
            case .or:
                body = "let left = \(childCall(0))\nlet right = \(childCall(1))\nreturn left + right"
            }
            let parameters = try bindings.map {
                "_ \(binder($0)): \(try swiftType(program.bindingTypes[$0]!))"
            }.joined(separator: ", ")
            declarations.append("""
            func _actionPart\(id.ordinal)(\(parameters)) throws -> [_Updates] {
                \(body)
            }
            """)
        }
        return declarations.joined(separator: "\n") + "\nreturn try _actionPart\(root.ordinal)()"
    }

    mutating func rawActionFunction(_ action: CompiledAction, collectionParameters: String) throws -> DeclSyntax {
        let parameters = try action.bindings.map {
            "\(binder($0.binder)): \(try swiftType(program.bindingTypes[$0.binder]!))"
        }.joined(separator: ", ")
        return DeclSyntax(stringLiteral: """
        private static func _updates\(action.id.ordinal)(from state: _ExecutionState\(parameters.isEmpty ? "" : ", " + parameters)\(collectionParameters), enabled: Set<Int>) throws -> [_Updates] {
            \(try actionFunctions(program.actions[action.id]!))
        }
        """)
    }

    private func enabledActionsCall(_ dependencies: Set<ActionID>, state: String, collectionArguments: String) -> String {
        guard !dependencies.isEmpty else { return "[]" }
        let identifiers = dependencies.map(\.ordinal).sorted().map(String.init).joined(separator: ", ")
        return "try Self._enabledActions(in: \(state)\(collectionArguments), required: [\(identifiers)])"
    }

    mutating func enabledDeclarations(collectionParameters: String, collectionArguments: String) throws -> [DeclSyntax] {
        var checks = ""
        for index in compilation.semantics.enabledActionIndices {
            let action = compilation.semantics.actions[index]
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
        private static func _enabledActions(in state: _ExecutionState\(collectionParameters), required: Set<Int>) throws -> Set<Int> {
            \(checks.isEmpty ? "return []" : "var result: Set<Int> = []\n" + checks + "\nreturn result")
        }
        """)
    }

    mutating func successorFunction(_ action: CompiledAction, surface: MachineSurfacePlan.Action, collectionParameters: String, collectionArguments: String) throws -> DeclSyntax {
        let parameters = try action.bindings.map { binding in
            "\(binder(binding.binder)): \(try swiftType(program.bindingTypes[binding.binder]!))"
        }.joined(separator: ", ")
        let arguments = action.bindings.map { "\(binder($0.binder)): \(binder($0.binder))" }.joined(separator: ", ")
        let filtering: String
        if let constraint = compilation.semantics.constraint {
            let dependencies = compilation.enabledActionDependencies(in: constraint)
            let enabled = dependencies.isEmpty ? "" : "let enabled = \(enabledActionsCall(dependencies, state: "state", collectionArguments: collectionArguments))\n"
            let enabledArgument = dependencies.isEmpty ? "[]" : "enabled"
            filtering = "let candidates = try updates.map { $0.applying(to: state) }.filter { state in\n\(enabled)return try Self._constraintHolds(in: state\(collectionArguments), enabled: \(enabledArgument))\n}"
        } else {
            filtering = "let candidates = updates.map { $0.applying(to: state) }"
        }
        return DeclSyntax(stringLiteral: """
        private static func _successors\(action.id.ordinal)(from state: _ExecutionState\(parameters.isEmpty ? "" : ", " + parameters)\(collectionParameters), enabled: Set<Int>) throws -> [_ExecutionState] {
            let updates = try _updates\(action.id.ordinal)(from: state\(arguments.isEmpty ? "" : ", " + arguments)\(collectionArguments), enabled: enabled)
            \(filtering)
            return candidates.reduce(into: [_ExecutionState]()) { states, state in
                if !states.contains(state) { states.append(state) }
            }
        }
        """)
    }

    mutating func dispatchDeclarations(collectionArguments: String) throws -> [DeclSyntax] {
        var cases: [String] = []
        var enumeration: [String] = []
        for surface in model.compilation.machineSurfacePlan.actions {
            guard let action = compilation.semantics.actions.first(where: { $0.id == surface.compiledAction }) else { throw unsupported("action dispatch") }
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
                    domain = nativeCollectionBinding(collection, in: model)
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
            let enabled = enabledActionsCall(compilation.semantics.enabledActionDependencies[action.id] ?? [],
                state: "_execution", collectionArguments: collectionArguments)
            cases.append("""
            case \(label):
                \(validations.joined(separator: "\n"))
                return try Self._successors\(action.id.ordinal)(from: _execution\(invocation.isEmpty ? "" : ", " + invocation.joined(separator: ", "))\(collectionArguments), enabled: \(enabled))
            """)
            let actionValue = ".\(surface.swiftIdentifier)" + (actionArguments.isEmpty ? "" : "(\(actionArguments.joined(separator: ", ")))")
            enumeration.append("do {\n" + loops + "let action: Action = \(actionValue)\nif try isEnabled(action) { result.append(action) }\n" + closing + "}\n")
        }
        return try nativeDeclarations("""
        private func _successors(for action: Action) throws -> [_ExecutionState] {
            switch action {
                \(cases.joined(separator: "\n"))
            }
        }
        public func isEnabled(_ action: Action) throws -> Bool {
            try !_successors(for: action).isEmpty
        }
        public func enabledActions() throws -> [Action] {
            \(enumeration.isEmpty ? "return []" : "var result: [Action] = []\n" + enumeration.joined(separator: "\n") + "\nreturn result")
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
        let arguments = model.compilation.machineSurfacePlan.collections.map { ", \($0.swiftIdentifier): \(nativeCollectionBinding($0, in: model))" }.joined()
        var declarations: [DeclSyntax] = []
        var checks: [String] = []
        if let constraint = program.constraint {
            declarations += try nativeDeclarations("""
            private static func _constraintHolds(in state: _ExecutionState\(collectionParameters), enabled: Set<Int>) throws -> Bool {
                \(try expression(constraint))
            }
            """)
        }
        for invariant in compilation.semantics.invariants {
            declarations += try nativeDeclarations("""
            private static func _invariant\(invariant.id.ordinal)(in state: _ExecutionState\(collectionParameters), enabled: Set<Int>) throws -> Bool {
                \(try expression(program.invariants[invariant.id]!))
            }
            """)
            let enabled = enabledActionsCall(compilation.enabledActionDependencies(in: invariant.body), state: "_execution", collectionArguments: arguments)
            checks.append("if try !Self._invariant\(invariant.id.ordinal)(in: _execution\(arguments), enabled: \(enabled)) { result.append(\(String(reflecting: invariant.name))) }")
        }
        declarations += try nativeDeclarations("""
        public func violatedInvariants() throws -> [String] {
            \(checks.isEmpty ? "return []" : "var result: [String] = []\n" + checks.joined(separator: "\n") + "\nreturn result")
        }
        """)
        if let assume = compilation.semantics.assume {
            let enabled = enabledActionsCall(compilation.enabledActionDependencies(in: assume), state: "_execution", collectionArguments: arguments)
            declarations += try nativeDeclarations("""
            private static func _assumptionsHold(in state: _ExecutionState\(collectionParameters), enabled: Set<Int>) throws -> Bool {
                \(try expression(program.assume!))
            }
            public func assumptionsHold() throws -> Bool {
                try Self._assumptionsHold(in: _execution\(arguments), enabled: \(enabled))
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
