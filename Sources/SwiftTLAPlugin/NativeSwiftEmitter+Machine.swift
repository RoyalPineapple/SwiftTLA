import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftParser
import SwiftTLA

extension NativeSwiftEmitter {
    mutating func machineMembers(nested: Bool = false) throws -> [DeclSyntax] {
        let api = model.api
        let collections = api.collections
        let collectionParameters = machineParameters
        let collectionArguments = machineArguments
        let appendedParameters = collectionParameters.isEmpty ? "" : ", \(collectionParameters)"
        let appendedArguments = collectionArguments.isEmpty ? "" : ", \(collectionArguments)"
        var declarations: [DeclSyntax] = []
        declarations += try configurationDeclarations()
        declarations += try propertyIdentityDeclarations()
        declarations += try validationDeclarations()
        let fields = try program.layout.variables.filter { stateMemberNames[$0.id] == nil }.map { variable in
            "let \(self.variable(variable.id)): \(try swiftType(program.variableTypes[variable.id]!))"
        }.joined(separator: "\n")
        declarations += try nativeDeclarations("""
        public struct CheckingRegisters: Sendable {}
        public func initialCheckingRegisters() throws -> CheckingRegisters { CheckingRegisters() }
        public func successors(checking context: inout CheckingContext<CheckingRegisters>) throws -> [(action: Action, machine: Self)] {
            try successors()
        }
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
            \(program.layout.parameters.isEmpty ? "" : "self.configuration = configuration")
            \(collections.map { "self.\($0.membersIdentifier) = \($0.membersIdentifier)" }.joined(separator: "\n"))
        }
        """)
        let configurationChecks = (program.layout.parameters.isEmpty ? [] : ["configuration == other.configuration"]) + collections.map {
            "\($0.membersIdentifier) == other.\($0.membersIdentifier)"
        }
        declarations += try nativeDeclarations("""
        public func hasSameConfiguration(as other: Self) -> Bool {
            \(configurationChecks.isEmpty ? "true" : configurationChecks.joined(separator: " && "))
        }
        """)
        let stateFields = try api.variables.map { variable in
            "public let \(variable.swiftIdentifier): \(try swiftType(program.variableTypes[variable.id]!))"
        }.joined(separator: "\n")
        let stateParameters = try api.variables.map { variable in
            "\(variable.swiftIdentifier) _value\(variable.id.ordinal): \(try swiftType(program.variableTypes[variable.id]!))"
        }.joined(separator: ", ")
        let stateAssignments = api.variables.map { "self.\($0.swiftIdentifier) = _value\($0.id.ordinal)" }.joined(separator: "\n")
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
        declarations += try formalProjectionDeclarations()
        declarations += try actionDeclarations()
        declarations += try updateDeclarations()
        declarations += try collectionValidationDeclarations(parameters: appendedParameters)
        declarations += try initialDeclarations(parameters: collectionParameters, arguments: collectionArguments)
        let emittedActionIDs = Set(api.actions.map(\.compiledAction)).union(enabledActionIDs)
        declarations += try program.behavior.actions.filter { emittedActionIDs.contains($0.id) }.map {
            try updateFunction($0, collectionParameters: appendedParameters)
        }
        declarations += try enabledDeclarations(collectionParameters: appendedParameters, collectionArguments: appendedArguments)
        let actionFunctions = try api.actions.map { apiAction in
            let action = program[apiAction.compiledAction]
            return try successorFunction(action, api: apiAction, collectionParameters: appendedParameters, collectionArguments: appendedArguments)
        }
        declarations += actionFunctions
        declarations += try dispatchDeclarations(collectionArguments: appendedArguments)
        declarations += try propertyDeclarations(collectionParameters: appendedParameters)
        declarations += try refinementDeclarations(nested: nested)
        if nested { return declarations }
        declarations += try exportDeclarations()
        declarations += actorMembers()
        if !program.layout.controlLocations.isEmpty {
            declarations += try nativeDeclarations("""
            @_documentation(visibility: internal)
            public enum _ControlLocation: Int, Hashable, Sendable {
                \(program.layout.controlLocations.map { "case location\($0.id.ordinal) = \($0.id.ordinal)" }.joined(separator: "\n"))
            }
            """)
        }
        let modelValues = typeDeclarations.modelValueCases.sorted { $0.key < $1.key }
        if !modelValues.isEmpty {
            declarations += try nativeDeclarations("""
            @_documentation(visibility: internal)
            public enum _ModelValue: String, Hashable, Sendable {
                \(modelValues.map { "case \($0.value) = \(String(reflecting: $0.key))" }.joined(separator: "\n"))
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
        let cases = try model.api.actions.map { api in
            let action = program[api.compiledAction]
            guard action.bindings.count == api.bindings.count else {
                throw unsupported("action binding layout")
            }
            if let collection = api.collection {
                guard action.bindings.count == 1 else { throw unsupported("collection action binding layout") }
                return "case \(api.swiftIdentifier)(member: \(collection.elementType).ID)"
            }
            let parameters = try zip(action.bindings, api.bindings).filter { $0.1.isPublic }.map { binding, apiBinding in
                "\(apiBinding.swiftIdentifier): \(try swiftType(program.bindingTypes[binding.binder]!))"
            }.joined(separator: ", ")
            return "case \(api.swiftIdentifier)" + (parameters.isEmpty ? "" : "(\(parameters))")
        }.joined(separator: "\n")
        return try nativeDeclarations("""
        public enum Action: Hashable, Sendable {
            \(cases)
        }
        """)
    }

    func collectionValidationDeclarations(parameters: String) throws -> [DeclSyntax] {
        let checks = model.api.variables.compactMap { variable -> String? in
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
        let validation = model.api.collections.map { collection in
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
        private static func _updates\(action.id.ordinal)(from state: Snapshot\(parameters.isEmpty ? "" : ", " + parameters)\(collectionParameters)) throws -> [_Updates] {
            \(try actionFunctions(action.body))
        }
        """)
    }

    mutating func actionDomain(_ binding: CompiledActionBinding, state: String) throws -> String {
        if let members = binding.literalMembers {
            return "[\(try members.map { try literal($0, as: program.bindingTypes[binding.binder]!) }.joined(separator: ", "))]"
        }
        return try expression(binding.domain, state: state)
    }

    mutating func enabledDeclarations(collectionParameters: String, collectionArguments: String) throws -> [DeclSyntax] {
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
            private static func _isEnabled\(action.id.ordinal)(in state: Snapshot\(collectionParameters)) throws -> Bool {
                \(loops)
                if try !_updates\(action.id.ordinal)(from: state\(arguments.isEmpty ? "" : ", " + arguments.joined(separator: ", "))\(collectionArguments)).isEmpty { return true }
                \(closing)
                return false
            }
            """)
        }
        return declarations
    }

    func successorFunction(_ action: CompiledAction, api: GeneratedMachineAPI.Action, collectionParameters: String, collectionArguments: String) throws -> DeclSyntax {
        let parameters = try action.bindings.map { binding in
            "\(binder(binding.binder)): \(try swiftType(program.bindingTypes[binding.binder]!))"
        }.joined(separator: ", ")
        let arguments = action.bindings.map { "\(binder($0.binder)): \(binder($0.binder))" }.joined(separator: ", ")
        return DeclSyntax(stringLiteral: """
        private static func _successors\(action.id.ordinal)(from state: Snapshot\(parameters.isEmpty ? "" : ", " + parameters)\(collectionParameters)) throws -> [Snapshot] {
            let updates = try _updates\(action.id.ordinal)(from: state\(arguments.isEmpty ? "" : ", " + arguments)\(collectionArguments))
            let candidates = updates.map { $0.applying(to: state) }
            return candidates.reduce(into: [Snapshot]()) { states, state in
                if !states.contains(state) { states.append(state) }
            }
        }
        """)
    }

    mutating func dispatchDeclarations(collectionArguments: String) throws -> [DeclSyntax] {
        guard !model.api.actions.isEmpty else {
            return try nativeDeclarations("""
            public func enabledActions() throws -> [Action] { [] }
            public func successors() throws -> [(action: Action, machine: Self)] { [] }
            public func formalCall(for action: Action) throws -> FormalActionCall {}
            """)
        }
        var cases: [String] = []
        var formalCases: [String] = []
        var enumeration: [String] = []
        for api in model.api.actions {
            let action = program[api.compiledAction]
            var pattern: [String] = []
            var invocation: [String] = []
            var validations: [String] = []
            var actionArguments: [String] = []
            var formalArguments: [String] = []
            var loops = ""
            var closing = ""
            for (binding, apiBinding) in zip(action.bindings, api.bindings) {
                let name = binder(binding.binder)
                let type = program.bindingTypes[binding.binder]!
                let domain: String
                if let collection = api.collection {
                    domain = collection.membersIdentifier
                    pattern.append("member: let \(name)")
                    actionArguments.append("member: \(name)")
                } else {
                    domain = try actionDomain(binding, state: "_execution.")
                    if apiBinding.isPublic {
                        pattern.append("\(apiBinding.swiftIdentifier): let \(name)")
                        actionArguments.append("\(apiBinding.swiftIdentifier): \(name)")
                    }
                }
                let argumentValue: String
                if apiBinding.isPublic || api.collection != nil {
                    argumentValue = name
                } else {
                    guard let value = binding.literalMembers?.first else {
                        throw unsupported("a hidden action argument requires a literal singleton domain")
                    }
                    argumentValue = try literal(value, as: type)
                }
                formalArguments.append(try formalValue(argumentValue, type: type))
                if apiBinding.isPublic || api.collection != nil {
                    if let collection = api.collection {
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
                    invocation.append("\(name): \(argumentValue)")
                }
            }
            let label = ".\(api.swiftIdentifier)" + (pattern.isEmpty ? "" : "(\(pattern.joined(separator: ", ")))")
            let formalName = program.layout.actions[action.id.ordinal].renderedName
            formalCases.append("case \(label): return FormalActionCall(name: \(String(reflecting: formalName)), arguments: [\(formalArguments.joined(separator: ", "))])")
            cases.append("""
            case \(label):
                \(validations.joined(separator: "\n"))
                return try Self._successors\(action.id.ordinal)(from: _execution\(invocation.isEmpty ? "" : ", " + invocation.joined(separator: ", "))\(collectionArguments))
            """)
            let actionValue = ".\(api.swiftIdentifier)" + (actionArguments.isEmpty ? "" : "(\(actionArguments.joined(separator: ", ")))")
            enumeration.append("do {\n" + loops + "result.append(\(actionValue))\n" + closing + "}\n")
        }
        return try nativeDeclarations("""
        public func formalCall(for action: Action) throws -> FormalActionCall {
            switch action {
                \(formalCases.joined(separator: "\n"))
            }
        }
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
        private func _actions() throws -> [Action] {
            var result: [Action] = []
            \(enumeration.joined(separator: "\n"))
            return result
        }
        public func successors() throws -> [(action: Action, machine: Self)] {
            try _actions().flatMap { action in
                try successors(for: action).map { (action, $0) }
            }
        }
        public func enabledActions() throws -> [Action] {
            try _actions().filter { try isEnabled($0) }
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
        let arguments = machineArguments.isEmpty ? "" : ", " + machineArguments
        var declarations: [DeclSyntax] = []
        var checks: [String] = []
        declarations += try nativeDeclarations("public static var checksDeadlock: Bool { \(program.behavior.checkDeadlock) }")
        if let constraint = program.behavior.constraint {
            declarations += try nativeDeclarations("""
            private static func _constraintHolds(in state: Snapshot\(collectionParameters)) throws -> Bool {
                \(try expression(constraint.expression))
            }
            public func satisfiesStateConstraint() throws -> Bool {
                try Self._constraintHolds(in: _execution\(arguments))
            }
            """)
        } else {
            declarations += try nativeDeclarations("public func satisfiesStateConstraint() throws -> Bool { true }")
        }
        for invariant in program.behavior.invariants {
            declarations += try nativeDeclarations("""
            private static func _invariant\(invariant.id.ordinal)(in state: Snapshot\(collectionParameters)) throws -> Bool {
                \(try expression(invariant.predicate.expression))
            }
            """)
            checks.append("if checking.contains(.\(propertyCases[invariant.id]!)), try !Self._invariant\(invariant.id.ordinal)(in: _execution\(arguments)) { result.append(.\(propertyCases[invariant.id]!)) }")
        }
        declarations += try nativeDeclarations("""
        public func violatedInvariants(checking: Set<Property> = Set(Property.allCases)) throws -> [Property] {
            \(checks.isEmpty ? "return []" : "var result: [Property] = []\n" + checks.joined(separator: "\n") + "\nreturn result")
        }
        """)
        var reachabilityChecks: [String] = []
        for property in program.behavior.reachabilityProperties {
            declarations += try nativeDeclarations("""
            private static func _reachable\(property.id.ordinal)(in state: Snapshot\(collectionParameters)) throws -> Bool {
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
                private static func \(function)(in state: Snapshot, nextState: Snapshot\(collectionParameters)\(boundParameters)) throws -> Bool {
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
                var \(name): [TemporalCondition<@Sendable (Snapshot, Snapshot) throws -> Bool>] = []
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
            "var result: [Property: TemporalCondition<@Sendable (Snapshot, Snapshot) throws -> Bool>] = [:]\n" + temporalProperties.joined(separator: "\n") + "\nreturn result")
        declarations += try nativeDeclarations("""
        public func temporalProperties(checking: Set<Property> = Set(Property.allCases)) throws -> [Property: TemporalCondition<@Sendable (Snapshot, Snapshot) throws -> Bool>] {
            \(propertyBody)
        }
        """)
        var fairness: [String] = []
        var configuredFairness: [String] = []
        for (index, condition) in program.behavior.fairness.enumerated() {
            let name: String
            let matcher: String
            let changes: String
            if let projection = condition.projection {
                let function = "_fairnessChanges\(index)"
                declarations += try nativeDeclarations("""
                private static func \(function)(in state: Snapshot, nextState: Snapshot\(collectionParameters)) throws -> Bool {
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
            case .actionCall(let call):
                let action = model.api.actions.first { $0.compiledAction == call.action }!
                let bindings = program[call.action].bindings
                let arguments = try zip(bindings.indices, call.arguments).compactMap { index, value -> String? in
                    guard action.bindings[index].isPublic || action.collection != nil else { return nil }
                    let name = action.collection == nil ? action.bindings[index].swiftIdentifier : "member"
                    return "\(name): \(try literal(value, as: program.bindingTypes[bindings[index].binder]!))"
                }
                let value = ".\(action.swiftIdentifier)" + (arguments.isEmpty ? "" : "(\(arguments.joined(separator: ", ")))")
                name = FormalActionCall(
                    name: program.layout.actions[call.action.ordinal].renderedName,
                    arguments: try call.arguments.map { try $0.rendered(using: program.layout) }
                ).description
                matcher = "{ \(captureList)action in action == \(value) }"
            case .eachAction(let id):
                let action = model.api.actions.first { $0.compiledAction == id }!
                let bindings = program[id].bindings
                var loops: [String] = []
                var arguments: [String] = []
                for (index, binding) in bindings.enumerated() {
                    try program.requireImmutableDomain(binding.domain, path: "fairness.\(id.ordinal).domain")
                    loops.append("for \(binder(binding.binder)) in \(try actionDomain(binding, state: "")) {")
                    if action.bindings[index].isPublic || action.collection != nil {
                        let label = action.collection == nil ? action.bindings[index].swiftIdentifier : "member"
                        arguments.append("\(label): \(binder(binding.binder))")
                    }
                }
                let value = ".\(action.swiftIdentifier)" + (arguments.isEmpty ? "" : "(\(arguments.joined(separator: ", ")))")
                configuredFairness.append(loops.joined(separator: "\n") + "\n" + """
                let _action: Action = \(value)
                _fairness.append((name: try formalCall(for: _action).description,
                    isStrong: \(condition.isStrong), matches: { [ _action ] in $0 == _action }, changes: \(changes)))
                """ + String(repeating: "\n}", count: loops.count))
                continue
            }
            fairness.append("(name: \(String(reflecting: name + (condition.projection == nil ? "" : " [projection \(index)]"))), isStrong: \(condition.isStrong), matches: \(matcher), changes: \(changes))")
        }
        declarations += try nativeDeclarations("""
        public func fairnessConditions() throws -> [(name: String, isStrong: Bool, matches: @Sendable (Action) -> Bool, changes: (@Sendable (Snapshot, Snapshot) throws -> Bool)?)] {
            \(configuredFairness.isEmpty ? "let" : "var") _fairness: [(name: String, isStrong: Bool, matches: @Sendable (Action) -> Bool, changes: (@Sendable (Snapshot, Snapshot) throws -> Bool)?)] = [\(fairness.joined(separator: ",\n"))]
            \(configuredFairness.joined(separator: "\n"))
            return _fairness.sorted { $0.name < $1.name }
        }
        """)
        if let assume = program.behavior.assume {
            declarations += try nativeDeclarations("""
            private static func _assumptionsHold(in state: Snapshot\(collectionParameters)) throws -> Bool {
                \(try expression(assume.expression))
            }
            public func assumptionsHold() throws -> Bool {
                try Self._assumptionsHold(in: _execution\(arguments))
            }
            """)
        } else {
            declarations += try nativeDeclarations("public func assumptionsHold() throws -> Bool { true }")
        }
        return declarations
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
