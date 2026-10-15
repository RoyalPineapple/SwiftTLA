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

    mutating func machineMembers(nested: Bool = false) throws -> [DeclSyntax] {
        let api = model.api
        let configurationParameters = machineParameters
        let configurationArguments = machineArguments
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
        let machineDeclarations = try nativeDeclarations("""
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
                                    _ visit: (Action, Self) throws -> Bool) throws -> Bool {
            var run: CheckingContext<CheckingRegisters>? = context
            defer { context = run! }
            return try _visitSuccessors(checking: &run, visit)
        }
        public func visitValidationOutcomes(checking context: inout CheckingContext<CheckingRegisters>,
                                            _ visit: (Action, Self) throws -> Bool,
                                            onEvaluationFailure: (Action, NativeMachineEvaluationError) throws -> Bool) throws -> Bool {
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
        try verifyGeneratedSnapshotOutput(machineDeclarations.first {
            $0.as(StructDeclSyntax.self)?.name.text == "Snapshot"
        }, hiddenFields: hiddenFields)
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
        public func hasSameConfiguration(as other: Self) -> Bool {
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
            return "\\State.\(variable.swiftIdentifier): .init(swiftName: \(String(reflecting: variable.swiftIdentifier)), formalName: \(String(reflecting: declaration.declaration.name)))"
        }.joined(separator: ",\n")
        let stateDeclarations = try nativeDeclarations("""
        public struct State: Hashable, GeneratedModelFields {
            \(stateFields)
            public static var displayNames: [PartialKeyPath<State>: String] {
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
        try verifyGeneratedStateConstructorOutput(stateDeclarations.first, fields: try api.variables.map {
            (name: $0.swiftIdentifier, type: try swiftType(program.variableTypes[$0.id]!),
             ordinal: $0.id.ordinal, formalName: program.layout.variables[$0.id.ordinal].declaration.name)
        })
        declarations += stateDeclarations
        declarations += try formalProjectionDeclarations()
        declarations += try actionDeclarations()
        declarations += try updateDeclarations()
        declarations += try initialDeclarations(parameters: configurationParameters, arguments: configurationArguments)
        let emittedActionIDs = Set(api.actions.map(\.compiledAction)).union(enabledActionIDs)
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
            public enum _ControlLocation: Int, Hashable, Sendable {
                \(program.layout.controlLocations.map { "case location\($0.id.ordinal) = \($0.id.ordinal)" }.joined(separator: "\n"))
            }
            """)
        }
        declarations += try valueTypeDeclarations()
        declarations += try choiceCacheDeclarations()
        return declarations
    }

    func valueTypeDeclarations() throws -> [DeclSyntax] {
        var declarations: [DeclSyntax] = []
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
            return "guard _NativeMachineOperations.mergeUpdate(&result.\(name), other.\(name)) else { return nil }"
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
            declarations.first, slots: program.layout.variables.map { variable($0.id) })
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

    mutating func initialDeclarations(parameters: String, arguments: String) throws -> [DeclSyntax] {
        let hasRandomSubset = hasRandomSubsetInitializer
        var code = "var result: [Snapshot] = []\nvar firstFailure: NativeMachineEvaluationError?\ntry _NativeMachineOperations.visitInitialBranch({\n"
        var closing = ""
        var expectedLoops: [String: String] = [:]
        var expectedCandidateSources: [String: String] = [:]
        var expectedMembershipSources: [String: String] = [:]
        for initialization in program.behavior.initializations {
            let type = program.variableTypes[initialization.variable]!
            let name = variable(initialization.variable)
            switch initialization.initialization {
            case .value(let expression):
                code += "let \(name): \(try swiftType(type)) = \(try self.expression(expression, state: ""))\n"
                if let field = stateMemberNames[initialization.variable] {
                    code += "if _selectedInitial == nil || _selectedInitial!.\(field) == \(name) {\n"
                    closing = "}\n" + closing
                }
            case .memberOf(let expression):
                let randomSubsetOperands: (count: CompiledExpression, domain: CompiledExpression)?
                if case .randomSubset = expression.computation.operation {
                    randomSubsetOperands = (expression.computation.children[0], expression.computation.children[1])
                } else {
                    randomSubsetOperands = nil
                }
                if let operands = randomSubsetOperands {
                    code += "let \(name)_sampleLimit = \(try self.expression(operands.count, state: ""))\n"
                    code += "try _NativeMachineOperations.validateRandomSubsetCount(\(name)_sampleLimit)\n"
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
                        sample = "try _NativeMachineOperations.randomFunctionSubset(upTo: \(name)_sampleLimit, from: \(from), to: \(to))"
                        exhaustive = "try _NativeMachineOperations.randomFunctionInitialSupport(upTo: \(name)_sampleLimit, from: \(from), to: \(to))"
                    } else {
                        sample = "try _NativeMachineOperations.randomSubset(upTo: \(name)_sampleLimit, from: \(domain))"
                        exhaustive = "try _NativeMachineOperations.randomSubsetInitialSupport(upTo: \(name)_sampleLimit, from: \(domain))"
                    }
                    candidateSource = "(_sampleRandomSubset ? (\(sample)) : (\(exhaustive))).sorted(by: \(try ordering(type)))"
                } else {
                    candidateSource = "\(try self.expression(expression, state: "")).sorted(by: \(try ordering(type)))"
                }
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
                    let \(name)Candidates: [\(try swiftType(type))] = try _NativeMachineOperations.initialCandidates(
                        selecting: _selectedInitial.map(\\.\(field)),
                        enumerate: { \(candidateSource) },
                        contains: { \(name) in
                        let \(name)_isMember = \(membershipSource)
                        return \(eligible)
                        }
                    )
                    for \(name) in \(name)Candidates {
                    try _NativeMachineOperations.visitInitialBranch({

                    """
                } else {
                    expectedLoops[name] = candidateSource
                    code += "for \(name) in \(candidateSource) {\ntry _NativeMachineOperations.visitInitialBranch({\n"
                }
                closing = """
                }, onEvaluationFailure: { failure in
                    if firstFailure == nil { firstFailure = failure }
                })
                }
                """ + closing
            }
        }
        if let selected = program.behavior.initialInvariant {
            let arguments = arguments.isEmpty ? "" : ", " + arguments
            code += "let candidate = \(executionState(values: variable))\n"
            code += "if try Self._invariant\(selected.ordinal)(in: candidate, atLevel: 0\(arguments)) { result.append(candidate) }\n"
        } else {
            code += "result.append(\(executionState(values: variable)))\n"
        }
        code += closing
        code += """
        }, onEvaluationFailure: { failure in
            if firstFailure == nil { firstFailure = failure }
        })
        return InitialEvaluationOutcomes(states: result, firstFailure: firstFailure)
        """
        let appendedParameters = parameters.isEmpty ? "" : ", " + parameters
        let appendedArguments = arguments.isEmpty ? "" : ", " + arguments
        let samplingParameter = hasRandomSubset ? ", _sampleRandomSubset: Bool = false" : ""
        var declarations = try nativeDeclarations("""
        private static func _initialStates(_selectedInitial: State? = nil\(samplingParameter)\(appendedParameters)) throws -> InitialEvaluationOutcomes<Snapshot> {
            \(code)
        }
        """)
        declarations += try nativeDeclarations("""
        private static func _completedInitialStates(_selectedInitial: State? = nil\(samplingParameter)\(appendedParameters)) throws -> [Snapshot] {
            let outcome = try _initialStates(_selectedInitial: _selectedInitial\(hasRandomSubset ? ", _sampleRandomSubset: _sampleRandomSubset" : "")\(appendedArguments))
            if let failure = outcome.firstFailure { throw failure }
            return outcome.states
        }
        public static func initialOutcomes(\(parameters)) throws -> InitialEvaluationOutcomes<Self> {
            let outcome = try _initialStates(\(arguments))
            return InitialEvaluationOutcomes(states: outcome.states.map { Self(execution: $0\(appendedArguments)) }, firstFailure: outcome.firstFailure)
        }
        public static func initialMachines(\(parameters)) throws -> [Self] {
            try _completedInitialStates(\(arguments)).map { Self(execution: $0\(appendedArguments)) }
        }
        public static func makeMachine(\(parameters)) throws -> Self {
            var candidates = try _completedInitialStates(\(arguments))[...]
            guard let execution = candidates.popFirst() else { throw GeneratedMachineError.noInitialState }
            guard candidates.isEmpty else { throw GeneratedMachineError.ambiguousInitialState }
            return Self(execution: execution\(appendedArguments))
        }
        public static func makeMachine(_ initial: State\(appendedParameters)) throws -> Self {
            var candidates = try _completedInitialStates(_selectedInitial: initial\(appendedArguments))[...]
            guard let execution = candidates.popFirst() else { throw GeneratedMachineError.invalidInitialState }
            guard candidates.isEmpty else { throw GeneratedMachineError.ambiguousInitialState }
            return Self(execution: execution\(appendedArguments))
        }
        """)
        if hasRandomSubset {
            declarations += try nativeDeclarations("""
            public static func sampledInitialMachines(\(parameters)) throws -> [Self] {
                try _completedInitialStates(_sampleRandomSubset: true\(appendedArguments)).map { Self(execution: $0\(appendedArguments)) }
            }
            """)
        }
        try verifyGeneratedInitialBindings(
            declarations.first { $0.as(FunctionDeclSyntax.self)?.name.text == "_initialStates" },
            expected: program.behavior.initializations.map { initialization in
                let name = variable(initialization.variable)
                switch initialization.initialization {
                case .value: return "let \(name)"
                case .memberOf: return "for \(name)"
                }
            }, expectedLoops: expectedLoops, expectedCandidateSources: expectedCandidateSources)
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
        try verifyGeneratedInitialConstruction(declarations, configured: !program.layout.parameters.isEmpty,
            sampled: hasRandomSubset)
        if hasRandomSubset {
            declarations += try selectedInitialDeclarations(arguments: arguments)
        }
        return declarations
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
                required = ["if _selectedInitial == nil || _selectedInitial!.\(field) == \(name) {"]
            case .memberOf(let expression):
                let eligible: String
                if case .randomSubset = expression.computation.operation {
                    eligible = "\(name)_sampleLimit > 0 && \(name)_isMember"
                } else {
                    eligible = "\(name)_isMember"
                }
                let type = program.variableTypes[initialization.variable]!
                required = [
                    "let \(name)Candidates: [\(try swiftType(type))] = try _NativeMachineOperations.initialCandidates(",
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
            let candidate = \(state)
            if try Self._invariant\(invariant.ordinal)(in: candidate, atLevel: 0\(configuration)) { result.append(candidate) }
            """
        } else {
            append = "result.append(\(state))"
        }
        let closing = program.behavior.initializations.reversed().map { initialization -> String in
            switch initialization.initialization {
            case .memberOf:
                return """
                }, onEvaluationFailure: { failure in
                    if firstFailure == nil { firstFailure = failure }
                })
                }

                """
            case .value:
                return stateMemberNames[initialization.variable] == nil ? "" : "}\n"
            }
        }.joined()
        let suffix = append + "\n" + closing + """
        }, onEvaluationFailure: { failure in
            if firstFailure == nil { firstFailure = failure }
        })
        return InitialEvaluationOutcomes(states: result, firstFailure: firstFailure)
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

    private func selectedInitialDeclarations(arguments: String) throws -> [DeclSyntax] {
        let decoded = try program.layout.variables.enumerated().compactMap { index, variable -> String? in
            guard stateMemberNames[variable.id] != nil else { return nil }
            let type = program.variableTypes[variable.id]!
            return """
            guard let _json\(index) = formalJSON.value(for: Self.__swifttlaFormalProjectionTokens[\(index)]) else {
                throw TLAStateProjectionDiagnostic.invalidKey(path: \(String(reflecting: variable.declaration.name)))
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
                try _NativeMachineOperations.visitAlternatives(\(domain).sorted(by: \(try ordering(element))), emit: emit) { \(binder(binding)), branchEmit in
                    \(childCall(child, binding: binding, emit: "branchEmit"))
                }
                """
            case .define(let binding, let value, let child):
                body = "let \(binder(binding)) = \(try expression(value))\n\(childCall(child, binding: binding))"
            case .ifElse(let condition, let yes, let no):
                let value = try expression(condition)
                body = """
                try _NativeMachineOperations.visitConditional({ \(value) },
                    ifTrue: { \(childCall(yes)) },
                    ifFalse: { \(childCall(no)) })
                """
                conditions.append((id: id, value: value))
            case .and(let lhs, let rhs):
                let right = childCall(rhs, updates: "candidate")
                body = childCall(lhs, emit: "{ candidate in \(right) }")
            case .or(let lhs, let rhs):
                body = """
                try _NativeMachineOperations.visitAlternatives([false, true], emit: emit) { second, branchEmit in
                    if second { \(childCall(rhs, emit: "branchEmit")) }
                    else { \(childCall(lhs, emit: "branchEmit")) }
                }
                """
            }
            let parameters = (try bindings.map {
                "_ \(binder($0)): \(try swiftType(program.bindingTypes[$0]!))"
            } + ["_ updates: _Updates", "_ emit: (_Updates) throws -> Void"]).joined(separator: ", ")
            declarations.append("""
            func _actionPart\(id)(\(parameters)) throws {
                \(body)
            }
            """)
        }
        return (declarations.joined(separator: "\n") + "\ntry _actionPart0(_Updates(), emit)",
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
                                                   _ emit: (_Updates) throws -> Void) throws {
            \(parts.source)
        }
        """)
        try verifyGeneratedActionWriteOutput(declaration, action: action.body, parts: parts.writes,
            conditions: parts.conditions)
        return declaration
    }

    mutating func actionDomain(_ binding: CompiledActionBinding, state: String) throws -> String {
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
            private static func _isEnabled\(action.id.ordinal)(in state: Snapshot\(configurationParameters)) throws -> Bool {
                var context: CheckingContext<CheckingRegisters>?
                return try _isEnabled\(action.id.ordinal)(in: state\(configurationArguments), checking: &context)
            }
            private static func _isEnabled\(action.id.ordinal)(in state: Snapshot\(configurationParameters), checking context: inout CheckingContext<CheckingRegisters>?) throws -> Bool {
                \(loops)
                var enabled = false
                try _visitUpdates\(action.id.ordinal)(from: state\(arguments.isEmpty ? "" : ", " + arguments.joined(separator: ", "))\(configurationArguments), checking: &context) { _ in enabled = true }
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
        return DeclSyntax(stringLiteral: """
        private static func _visitSuccessors\(action.id.ordinal)(from state: Snapshot\(parameters.isEmpty ? "" : ", " + parameters)\(configurationParameters), checking context: inout CheckingContext<CheckingRegisters>?,
                                                      _ visit: (Snapshot) throws -> Void) throws {
            var emitted: [Snapshot] = []
            try _visitUpdates\(action.id.ordinal)(from: state\(arguments.isEmpty ? "" : ", " + arguments)\(configurationArguments), checking: &context) { updates in
                let candidate = updates.applying(to: state)
                if !emitted.contains(candidate) {
                    emitted.append(candidate)
                    try visit(candidate)
                }
            }
        }
        """)
    }

    mutating func dispatchDeclarations(configurationArguments: String) throws -> [DeclSyntax] {
        guard !model.api.actions.isEmpty else {
            return try nativeDeclarations("""
            public func actionCandidates() throws -> [Action] { [] }
            public func enabledActions() throws -> [Action] { [] }
            public func successors() throws -> [(action: Action, machine: Self)] { [] }
            private func _successors(checking context: inout CheckingContext<CheckingRegisters>?) throws -> [(action: Action, machine: Self)] { [] }
            private func _visitSuccessors(checking context: inout CheckingContext<CheckingRegisters>?,
                                          _ visit: (Action, Self) throws -> Bool) throws -> Bool { false }
            private func _visitSuccessors(checking context: inout CheckingContext<CheckingRegisters>?,
                                          _ visit: (Action, Self) throws -> Bool,
                                          onEvaluationFailure: (Action, NativeMachineEvaluationError) throws -> Bool) throws -> Bool { false }
            public func formalCall(for action: Action) throws -> FormalActionCall {}
            """)
        }
        var visitorCases: [String] = []
        var formalCases: [String] = []
        var enumeration: [String] = []
        var visitorEnumeration: [String] = []
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
                let domain = try actionDomain(binding, state: "_execution.")
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
                    visitorValidations.append("guard \(domain).contains(\(name)) else { return }")
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
                try Self._visitSuccessors\(action.id.ordinal)(from: _execution\(invocation.isEmpty ? "" : ", " + invocation.joined(separator: ", "))\(configurationArguments), checking: &context, visit)
            """)
            let actionValue = ".\(api.swiftIdentifier)" + (actionArguments.isEmpty ? "" : "(\(actionArguments.joined(separator: ", ")))")
            enumeration.append("do {\n" + loops + "result.append(\(actionValue))\n" + closing + "}\n")
            visitorEnumeration.append("do {\n" + loops + "try _visitAction(\(actionValue))\n" + closing + "}\n")
        }
        return try nativeDeclarations("""
        public func visitSuccessors(for action: Action, checking context: inout CheckingContext<CheckingRegisters>,
                                    _ visit: (Self) throws -> Bool) throws -> Bool {
            var run: CheckingContext<CheckingRegisters>? = context
            defer { context = run! }
            var found = false
            do {
                try _visitSuccessors(for: action, checking: &run) { execution in
                    found = true
                    if try !visit(Self(execution: execution\(configurationArguments))) {
                        throw _StopSuccessorTraversal()
                    }
                }
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
            try _visitSuccessors(for: action, checking: &context) { result.append($0) }
            return result
        }
        private func _visitSuccessors(for action: Action, checking context: inout CheckingContext<CheckingRegisters>?,
                                      _ visit: (Snapshot) throws -> Void) throws {
            switch action {
                \(visitorCases.joined(separator: "\n"))
            }
        }
        public func isEnabled(_ action: Action) throws -> Bool {
            try !_successors(for: action).isEmpty
        }
        public func successors(for action: Action) throws -> [Self] {
            try _successors(for: action).map { execution in
                return Self(execution: execution\(configurationArguments))
            }
        }
        private func _actions() throws -> [Action] {
            var result: [Action] = []
            \(enumeration.joined(separator: "\n"))
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
                                      _ visit: (Action, Self) throws -> Bool) throws -> Bool {
            try _visitSuccessors(checking: &context, visit, onEvaluationFailure: { action, reason in
                throw MachineActionEvaluationFailure(action: action, reason: reason)
            })
        }
        private func _visitSuccessors(checking context: inout CheckingContext<CheckingRegisters>?,
                                      _ visit: (Action, Self) throws -> Bool,
                                      onEvaluationFailure: (Action, NativeMachineEvaluationError) throws -> Bool) throws -> Bool {
            var found = false
            do {
                func _visitAction(_ action: Action) throws {
                    var callbackFailed = false
                    do {
                        try _visitSuccessors(for: action, checking: &context) { execution in
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
                    } catch let reason as NativeMachineEvaluationError where !callbackFailed {
                        if try !onEvaluationFailure(action, reason) {
                            throw _StopSuccessorTraversal()
                        }
                    } catch {
                        throw error
                    }
                }
                \(visitorEnumeration.joined(separator: "\n"))
            } catch is _StopSuccessorTraversal {
            }
            return found
        }
        private struct _StopSuccessorTraversal: Error {}
        public func enabledActions() throws -> [Action] {
            try _actions().filter { try isEnabled($0) }
        }
        public mutating func send(_ action: Action) throws -> Transition {
            var candidates = try _successors(for: action)[...]
            guard let next = candidates.popFirst() else { throw GeneratedMachineError.noMatchingSuccessor }
            guard candidates.isEmpty else { throw GeneratedMachineError.ambiguousAction }
            let before = state
            _execution = next
            return Transition(action: action, before: before, after: state)
        }
        """)
    }

    mutating func propertyDeclarations(configurationParameters: String) throws -> [DeclSyntax] {
        let arguments = machineArguments.isEmpty ? "" : ", " + machineArguments
        var declarations: [DeclSyntax] = []
        var checks: [String] = []
        declarations += try nativeDeclarations("public static var checksDeadlock: Bool { \(program.behavior.checkDeadlock) }")
        declarations += try nativeDeclarations("public static var hasActionConstraint: Bool { \(program.behavior.actionConstraint != nil) }")
        if let constraint = program.behavior.constraint {
            declarations += try nativeDeclarations("""
            private static func _constraintHolds(in state: Snapshot\(configurationParameters)) throws -> Bool {
                \(try expression(constraint.expression))
            }
            public func satisfiesStateConstraint() throws -> Bool {
                try Self._constraintHolds(in: _execution\(arguments))
            }
            """)
        } else {
            declarations += try nativeDeclarations("public func satisfiesStateConstraint() throws -> Bool { true }")
        }
        if let actionConstraint = program.behavior.actionConstraint {
            let previousCheckingContextName = checkingContextName
            checkingContextName = "context"
            let body = try expression(actionConstraint.expression)
            checkingContextName = previousCheckingContextName
            declarations += try nativeDeclarations("""
            private static func _actionConstraintHolds(in state: Snapshot, nextState: Snapshot,
                checking context: inout CheckingContext<CheckingRegisters>?\(configurationParameters)) throws -> Bool {
                \(body)
            }
            public func satisfiesActionConstraint(to successor: Self,
                checking context: inout CheckingContext<CheckingRegisters>) throws -> Bool {
                var run: CheckingContext<CheckingRegisters>? = context
                defer { context = run! }
                return try Self._actionConstraintHolds(in: _execution, nextState: successor._execution,
                    checking: &run\(arguments))
            }
            """)
        } else {
            declarations += try nativeDeclarations("""
            public func satisfiesActionConstraint(to successor: Self,
                checking context: inout CheckingContext<CheckingRegisters>) throws -> Bool { true }
            """)
        }
        for invariant in program.behavior.invariants {
            let previousCheckingLevelName = checkingLevelName
            checkingLevelName = "level"
            defer { checkingLevelName = previousCheckingLevelName }
            declarations += try nativeDeclarations("""
            private static func _invariant\(invariant.id.ordinal)(in state: Snapshot, atLevel level: Int\(configurationParameters)) throws -> Bool {
                \(try expression(invariant.predicate.expression))
            }
            """)
            checks.append("if checking.contains(.\(propertyCases[invariant.id]!)), try !Self._invariant\(invariant.id.ordinal)(in: _execution, atLevel: level\(arguments)) { result.append(.\(propertyCases[invariant.id]!)) }")
        }
        declarations += try nativeDeclarations("""
        public static var invariantProperties: [Property] { [\(program.behavior.invariants.map { ".\(propertyCases[$0.id]!)" }.joined(separator: ", "))] }
        public func violatedInvariants(checking: Set<Property> = Set(Property.allCases), atLevel level: Int) throws -> [Property] {
            \(checks.isEmpty ? "return []" : "var result: [Property] = []\n" + checks.joined(separator: "\n") + "\nreturn result")
        }
        """)
        var reachabilityChecks: [String] = []
        for property in program.behavior.reachabilityProperties {
            declarations += try nativeDeclarations("""
            private static func _reachable\(property.id.ordinal)(in state: Snapshot\(configurationParameters)) throws -> Bool {
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
                private static func \(function)(in state: Snapshot, nextState: Snapshot\(configurationParameters)\(boundParameters)) throws -> Bool {
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
            private static func _assumptionsHold(in state: Snapshot\(configurationParameters)) throws -> Bool {
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
                private static func \(function)(in state: Snapshot, nextState: Snapshot\(configurationParameters)) throws -> Bool {
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
            \(configuredFairness.isEmpty ? "let" : "var") _fairness: [(name: String, isStrong: Bool, matches: @Sendable (Action) -> Bool, changes: (@Sendable (Snapshot, Snapshot) throws -> Bool)?)] = [\(fairness.joined(separator: ",\n"))]
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
            "try _NativeMachineOperations.validateRandomSubsetCount(\(name)_sampleLimit)",
            "try _NativeMachineOperations.\(sample)(upTo: \(name)_sampleLimit",
            "try _NativeMachineOperations.\(exhaustive)(upTo: \(name)_sampleLimit",
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
    let arguments = configured ? "configuration: configuration" : ""
    let appendedParameters = configured ? ", configuration: Configuration" : ""
    let appendedArguments = configured ? ", configuration: configuration" : ""
    let samplingParameter = sampled ? ", _sampleRandomSubset: Bool = false" : ""
    let expected = Parser.parse(source: """
    private static func _completedInitialStates(_selectedInitial: State? = nil\(samplingParameter)\(appendedParameters)) throws -> [Snapshot] {
        let outcome = try _initialStates(_selectedInitial: _selectedInitial\(sampled ? ", _sampleRandomSubset: _sampleRandomSubset" : "")\(appendedArguments))
        if let failure = outcome.firstFailure { throw failure }
        return outcome.states
    }
    public static func initialOutcomes(\(parameters)) throws -> InitialEvaluationOutcomes<Self> {
        let outcome = try _initialStates(\(arguments))
        return InitialEvaluationOutcomes(states: outcome.states.map { Self(execution: $0\(appendedArguments)) }, firstFailure: outcome.firstFailure)
    }
    public static func initialMachines(\(parameters)) throws -> [Self] {
        try _completedInitialStates(\(arguments)).map { Self(execution: $0\(appendedArguments)) }
    }
    public static func makeMachine(\(parameters)) throws -> Self {
        var candidates = try _completedInitialStates(\(arguments))[...]
        guard let execution = candidates.popFirst() else { throw GeneratedMachineError.noInitialState }
        guard candidates.isEmpty else { throw GeneratedMachineError.ambiguousInitialState }
        return Self(execution: execution\(appendedArguments))
    }
    public static func makeMachine(_ initial: State\(appendedParameters)) throws -> Self {
        var candidates = try _completedInitialStates(_selectedInitial: initial\(appendedArguments))[...]
        guard let execution = candidates.popFirst() else { throw GeneratedMachineError.invalidInitialState }
        guard candidates.isEmpty else { throw GeneratedMachineError.ambiguousInitialState }
        return Self(execution: execution\(appendedArguments))
    }
    \(sampled ? """
    public static func sampledInitialMachines(\(parameters)) throws -> [Self] {
        try _completedInitialStates(_sampleRandomSubset: true\(appendedArguments)).map { Self(execution: $0\(appendedArguments)) }
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

func verifyGeneratedInitialBindings(
    _ declaration: DeclSyntax?, expected: [String], expectedLoops: [String: String],
    expectedCandidateSources: [String: String]
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
    _ declaration: DeclSyntax?, hiddenFields: [(name: String, type: String)]
) throws {
    let fields = hiddenFields.map { "let \($0.name): \($0.type)" }.joined(separator: "\n")
    let expected = Parser.parse(source: """
    public struct Snapshot: Hashable, Sendable {
        public let state: State
        \(fields)
    }
    """).statements.first?.item.as(StructDeclSyntax.self)
    let actualTokens = declaration.map { Array($0.tokens(viewMode: .sourceAccurate)).map(\.text) }
    let expectedTokens = expected.map { Array($0.tokens(viewMode: .sourceAccurate)).map(\.text) }
    guard actualTokens == expectedTokens else {
        throw CompilationDiagnostic(
            code: .unsupportedGeneratedValueShape, stage: .validation,
            path: "native.Snapshot",
            expected: "the public state and every hidden field with compiler-synthesized identity",
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

func verifyGeneratedUpdateMergeOutput(_ declaration: DeclSyntax?, slots: [String]) throws {
    let merge = declaration?.as(StructDeclSyntax.self)?.memberBlock.members.compactMap {
        $0.decl.as(FunctionDeclSyntax.self)
    }.first { $0.name.text == "merging" }
    var expected = ["func", "merging", "(", "_", "other", ":", "Self", ")", "->", "Self", "?", "{",
                    "var", "result", "=", "self"]
    for slot in slots {
        expected += ["guard", "_NativeMachineOperations", ".", "mergeUpdate", "(", "&", "result", ".",
                     slot, ",", "other", ".", slot, ")", "else", "{", "return", "nil", "}"]
    }
    expected += ["return", "result", "}"]
    guard let merge,
          Array(merge.tokens(viewMode: .sourceAccurate)).map(\.text) == expected else {
        throw CompilationDiagnostic(
            code: .unsupportedGeneratedValueShape, stage: .validation,
            path: "native._Updates.merging",
            expected: "one mergeUpdate call per compiled state slot in declaration order",
            actual: "the generated merge method differs from the checked rule",
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

func verifyGeneratedActionWriteOutput(
    _ declaration: DeclSyntax?, action: CompiledActionExpr,
    parts: [(id: Int, slot: String, value: String)],
    conditions: [(id: Int, value: String)] = []
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
    let visitorTokens = Array(visitor.tokens(viewMode: .sourceAccurate)).map(\.text)
    var tokenDepths: [Int] = []
    tokenDepths.reserveCapacity(visitorTokens.count)
    var depth = 0
    for token in visitorTokens {
        tokenDepths.append(depth)
        if token == "{" { depth += 1 }
        if token == "}" { depth -= 1 }
    }
    var bodies: [Int: [String]] = [:]
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
        bodies[id] = Array(visitorTokens[(open + 1)..<(close - 1)])
    }
    let expectedEntry = ["try", "_actionPart0", "(", "_Updates", "(", ")", ",", "emit", ")"]
    let rootCalls = visitorTokens.indices.filter { index in
        tokenDepths[index] == 1 && index + expectedEntry.count <= visitorTokens.count &&
            Array(visitorTokens[index..<(index + expectedEntry.count)]) == expectedEntry
    }
    guard rootCalls.count == 1 else {
        throw invalid("native.action.entry", "one call to the root action part",
            "found \(rootCalls.count) root calls")
    }

    var pending: [(id: Int, node: CompiledActionExpr)] = [(0, action)]
    var expectedChildren: [Int: [Int]] = [:]
    var alternatives: [Int] = []
    var conditionals: [Int] = []
    var nextID = 1
    var expectedWriteCount = 0
    while let (id, node) = pending.popLast() {
        switch node {
        case .assign, .unchanged:
            expectedWriteCount += 1
            expectedChildren[id] = []
        case .guard_:
            expectedChildren[id] = []
        case .existsAction(_, _, let body), .define(_, _, let body):
            expectedChildren[id] = [nextID]
            pending.append((nextID, body))
            nextID += 1
        case .ifElse(_, let yes, let no):
            expectedChildren[id] = [nextID, nextID + 1]
            conditionals.append(id)
            pending.append((nextID, yes))
            pending.append((nextID + 1, no))
            nextID += 2
        case .and(let lhs, let rhs):
            expectedChildren[id] = [nextID + 1, nextID]
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
        let expected = ["try", "_NativeMachineOperations", ".", "visitAlternatives", "(",
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
        let expected = Parser.parse(source: """
        func proof() {
            try _NativeMachineOperations.visitConditional({ \(condition.value) },
                ifTrue: { \(yes.joined(separator: " ")) },
                ifFalse: { \(no.joined(separator: " ")) })
        }
        """).statements.first?.item.as(FunctionDeclSyntax.self)
        let expectedBody = expected?.body?.statements.tokens(viewMode: .sourceAccurate).map(\.text) ?? []
        guard tokens == expectedBody else {
            throw invalid("native.action.conditional.\(id)",
                "the compiled condition selects exactly its corresponding child",
                "generated conditional body differs from the checked rule")
        }
    }
    guard parts.count == expectedWriteCount, Set(parts.map { $0.id }).count == parts.count else {
        throw CompilationDiagnostic(
            code: .unsupportedGeneratedValueShape, stage: .validation,
            path: "native.action.write", expected: "one unique generated write per compiled assignment or frame",
            actual: "found \(parts.count) write parts for \(expectedWriteCount) compiled writes",
            nextSafeAction: "Report this native code generation failure."
        )
    }
    for part in parts {
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
