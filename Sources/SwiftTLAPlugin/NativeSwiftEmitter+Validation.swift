import SwiftParser
import SwiftSyntax
import SwiftTLA

extension NativeSwiftEmitter {
    func propertyIdentityDeclarations() throws -> [DeclSyntax] {
        let properties = program.layout.properties
        let names = properties.map(\.formalName)
        let identifiers = properties.map { propertyCases[$0.id]! }
        let cases = identifiers.map { "case \($0)" }.joined(separator: "\n")
        let projections = zip(identifiers, names).map {
            ".\($0.0): \(String(reflecting: $0.1))"
        }.joined(separator: ",\n")
        let displayNames = properties.map { program.layout.propertyDisplayName($0.id) ?? $0.declaration.name }
        let displayProjections = zip(identifiers, displayNames).map {
            ".\($0.0): \(String(reflecting: $0.1))"
        }.joined(separator: ",\n")
        return try nativeDeclarations("""
        public enum Property: Hashable, CaseIterable, Sendable {
            \(cases)
        }
        public static var formalPropertyNames: [Property: \(nativeStringType)] {
            [\(identifiers.isEmpty ? ":" : projections)]
        }
        public static var propertyDisplayNames: [Property: \(nativeStringType)] {
            [\(identifiers.isEmpty ? ":" : displayProjections)]
        }
        """)
    }

    mutating func validationDeclarations() throws -> [DeclSyntax] {
        guard !program.behavior.validationScenarios.isEmpty else { return [] }
        let properties = program.layout.properties
        let identifiers = properties.map { propertyCases[$0.id]! }
        let hasConfiguration = !program.layout.parameters.isEmpty
        var scenarios: [String] = []
        var viewRuns: [String] = []
        var viewProjections: [String] = []
        var postconditionCases: [String] = []
        for (index, scenario) in program.behavior.validationScenarios.enumerated() {
            if let postcondition = scenario.postcondition {
                var pending = [postcondition]
                var visitedFunctions: Set<ResolvedFunctionID> = []
                while let current = pending.popLast() {
                    switch current.operation {
                    case .stateVariable, .checkingLevel, .checkingRegister, .setCheckingRegister,
                         .enabledAction, .nextState, .stutteringStep:
                        throw unsupported("postcondition depends on model state or a state-level checking value")
                    case .call(let id) where visitedFunctions.insert(id).inserted:
                        pending.append(program[id].body)
                    default: break
                    }
                    pending.append(contentsOf: current.children)
                }
                let previousCheckingDiameterName = checkingDiameterName
                checkingDiameterName = "summary.maximumLevel"
                defer { checkingDiameterName = previousCheckingDiameterName }
                postconditionCases.append("case \(index): return \(try expression(postcondition, state: ""))")
            }
            if let view = scenario.view {
                let previousCheckingLevelName = checkingLevelName
                checkingLevelName = "level"
                defer { checkingLevelName = previousCheckingLevelName }
                let identity = try expression(view, state: "machine.snapshot.")
                let projected = try expression(view, state: "snapshot.")
                viewRuns.append("""
                case \(index):
                    return try MachineValidator.run(initialOutcomes: initialOutcomes, maximumStates: maximumStates,
                        checking: checking, stopOnViolation: stopOnViolation,
                        stopOnReachability: stopOnReachability, fairness: fairness,
                        identity: { machine, level in \(identity) }, emit: emit)
                """)
                viewProjections.append("""
                case \(index):
                    return try SwiftTLA.TLAStateProjection(validating: [
                        .init(token: SwiftTLA.TLAStateProjection.Token(validating: "View")!,
                              value: \(try formalValue(projected, type: view.resultType)))])
                """)
            }
            let bindings = try program.layout.parameters.map { parameter in
                guard let value = scenario.bindings[parameter.binder] else {
                    throw unsupported("missing scenario binding: \(parameter.reference.name)")
                }
                return "\(parameter.reference.name): \(try expression(value, state: ""))"
            }.joined(separator: ", ")
            let selected = zip(properties, identifiers).filter { scenario.checks.contains($0.0.id) }
            let expectations = selected.map { property, identifier in
                ".\(identifier): .\((scenario.expectations[property.id] ?? .satisfied).rawValue)"
            }.joined(separator: ", ")
            let deadlock = scenario.checkDeadlock
                ? ".\((scenario.deadlockExpectation ?? .satisfied).rawValue)" : "nil"
            let symmetry = scenario.symmetry.map { String(reflecting: "Symm\($0.variableName)") } ?? "nil"
            let profileName = scenario.fairnessProfileIndex.map {
                String(reflecting: program.behavior.fairnessProfiles[$0].name)
            } ?? "nil"
            let checkingMode = switch scenario.checkingMode {
            case .exhaustive: ".exhaustive"
            case .decisiveCounterexample: ".decisiveCounterexample"
            case .simulation(let traces, let maximumDepth):
                ".simulation(traces: \(traces), maximumDepth: \(maximumDepth))"
            }
            scenarios.append("""
            ValidationScenario(name: \(String(reflecting: scenario.name)),
                displayName: \(String(reflecting: scenario.displayLabel ?? scenario.name)),
                \(hasConfiguration ? "configuration: try Configuration(\(bindings))," : "")
                checking: ModelChecks(properties: [\(selected.map { ".\($0.1)" }.joined(separator: ", "))], checkDeadlock: \(scenario.checkDeadlock)),
                checkingMode: \(checkingMode),
                behavior: .\(scenario.behavior.rawValue),
                selectedSymmetry: \(symmetry),
                selectedFairnessProfile: \(scenario.fairnessProfileIndex.map(String.init) ?? "nil"),
                selectedFairnessProfileName: \(profileName),
                selectedView: \(scenario.view == nil ? "nil" : String(index)),
                selectedPostcondition: \(scenario.postcondition == nil ? "nil" : String(index)),
                postconditionName: \(scenario.postconditionName.map(String.init(reflecting:)) ?? "nil"),
                postconditionExpectation: \(scenario.postconditionExpectation.map { ".\($0.rawValue)" } ?? "nil"),
                expectations: [\(selected.isEmpty ? ":" : expectations)],
                deadlockExpectation: \(deadlock))
            """)
        }
        let arguments = hasConfiguration ? "configuration: configuration" : ""
        let hasRandomSubset = hasRandomSubsetInitializer
        let declarations = try nativeDeclarations("""
        public struct ValidationScenario: ModelValidationScenario {
            public typealias Machine = \(model.typeName)
            public typealias Property = \(model.typeName).Property
            public let name: \(nativeStringType)
            public let displayName: \(nativeStringType)
            \(hasConfiguration ? "public let configuration: Configuration" : "")
            public let checking: ModelChecks<Property>
            public let checkingMode: ValidationCheckingMode
            public let behavior: ModelBehavior
            let selectedSymmetry: \(nativeStringType)?
            let selectedFairnessProfile: \(nativeIntType)?
            let selectedFairnessProfileName: \(nativeStringType)?
            let selectedView: \(nativeIntType)?
            let selectedPostcondition: \(nativeIntType)?
            public let postconditionName: \(nativeStringType)?
            public let postconditionExpectation: ValidationExpectation?
            public let expectations: [Property: ValidationExpectation]
            public let deadlockExpectation: ValidationExpectation?
            public var usesView: \(nativeBoolType) { selectedView != nil }

            public func postconditionSatisfied(after summary: MachineValidationSummary<Property>) throws -> \(nativeBoolType)? {
                guard case .exhausted = summary.completion else { return nil }
                switch selectedPostcondition {
                \(postconditionCases.joined(separator: "\n"))
                case nil: return nil
                default: throw ExplorationError.configurationMismatch
                }
            }

            public func initialOutcomes() throws -> SwiftTLA.InitialEvaluationOutcomes<Machine> {
                \(hasRandomSubset ? "if case .simulation = checkingMode { return try .init(states: \(model.typeName).sampledInitialMachines(\(arguments)), failures: []) }" : "")
                return try \(model.typeName).initialOutcomes(\(arguments))
            }
            public func initialMachines() throws -> [\(model.typeName)] {
                let outcome = try initialOutcomes()
                if let failure = outcome.firstFailure { throw failure }
                return outcome.states
            }
            public var formalPropertyNames: [Property: \(nativeStringType)] {
                Machine.formalPropertyNames
            }
            public func fairnessConditions(on machine: Machine) throws -> [MachineFairnessCondition<Machine.Snapshot, Machine.Action>] {
                switch selectedFairnessProfile {
                \(program.behavior.fairnessProfiles.indices.map { index in
                    "case \(index): return try machine._fairnessProfile\(index)Conditions()"
                }.joined(separator: "\n"))
                case nil: return try machine.fairnessConditions()
                default: throw ExplorationError.configurationMismatch
                }
            }
            public func runValidation(initialMachines: [Machine], maximumStates: \(nativeIntType), checking: ModelChecks<Property>,
                stopOnViolation: \(nativeBoolType), stopOnReachability: \(nativeBoolType),
                fairness: [MachineFairnessCondition<Machine.Snapshot, Machine.Action>] = [],
                emit: (MachineValidationEvent<Machine>) throws -> Void) throws -> MachineValidationSummary<Property> {
                try runValidation(initialOutcomes: .init(states: initialMachines, failures: []),
                    maximumStates: maximumStates, checking: checking,
                    stopOnViolation: stopOnViolation, stopOnReachability: stopOnReachability, fairness: fairness, emit: emit)
            }
            public func runValidation(initialOutcomes: SwiftTLA.InitialEvaluationOutcomes<Machine>, maximumStates: \(nativeIntType),
                checking: ModelChecks<Property>, stopOnViolation: \(nativeBoolType), stopOnReachability: \(nativeBoolType),
                fairness: [MachineFairnessCondition<Machine.Snapshot, Machine.Action>] = [],
                emit: (MachineValidationEvent<Machine>) throws -> Void) throws -> MachineValidationSummary<Property> {
                switch selectedView {
                \(viewRuns.joined(separator: "\n"))
                case nil:
                    return try MachineValidator.run(initialOutcomes: initialOutcomes, maximumStates: maximumStates,
                        checking: checking, stopOnViolation: stopOnViolation,
                        stopOnReachability: stopOnReachability, fairness: fairness, emit: emit)
                default: throw ExplorationError.configurationMismatch
                }
            }
            public func formalIdentityProjection(of snapshot: Machine.Snapshot, using machine: Machine,
                atLevel level: \(nativeIntType)) throws -> SwiftTLA.TLAStateProjection {
                switch selectedView {
                \(viewProjections.joined(separator: "\n"))
                case nil:
                    return try machine.formalProjection(of: snapshot)
                default: throw ExplorationError.configurationMismatch
                }
            }
            public func render() throws -> RenderedSpecification {
                try \(model.typeName).render(\(arguments)).selectingChecks(checking,
                    formalPropertyNames: Machine.formalPropertyNames, behavior: behavior,
                    symmetry: selectedSymmetry, fairnessProfile: selectedFairnessProfileName,
                    view: selectedView.map { "__SwiftTLAView\\($0)" },
                    postcondition: postconditionName)
            }
        }
        public static func validationScenarios() throws -> [ValidationScenario] {
            [\(scenarios.joined(separator: ",\n"))]
        }
        """)
        if program.requiresSourceDefaultDeadlockOutput && viewRuns.isEmpty && !hasRandomSubset {
            try verifyOrderedIntValidationOutput(declarations, model: model, arguments: arguments)
        }
        return declarations
    }
}

func verifyOrderedIntValidationOutput(_ declarations: [DeclSyntax], model: MacroCompilation,
                                      arguments: String) throws {
    let modelName = model.typeName
    func mismatch() -> CompilationDiagnostic {
        CompilationDiagnostic(code: .unsupportedGeneratedValueShape, stage: .validation,
            path: "native.validation.initialOutcome",
            expected: "the ordered Int initial outcomes and failures reach the shared checker",
            actual: "the generated validation scenario changes or discards an initial outcome",
            nextSafeAction: "Report this generated validation translation failure.")
    }
    let structures = declarations.compactMap { $0.as(StructDeclSyntax.self) }
        .filter { $0.name.text == "ValidationScenario" }
    guard structures.count == 1, let members = structures.first?.memberBlock.members else {
        throw mismatch()
    }
    func actual(_ name: String, firstParameter: String? = nil) -> FunctionDeclSyntax? {
        members.compactMap { $0.decl.as(FunctionDeclSyntax.self) }.first {
            $0.name.text == name && $0.signature.parameterClause.parameters.first?.firstName.text == firstParameter
        }
    }
    func matches(_ declaration: FunctionDeclSyntax?, expected source: String) -> Bool {
        guard let expected = Parser.parse(source: source).statements.first?.item.as(FunctionDeclSyntax.self),
              let declaration else { return false }
        return Array(declaration.tokens(viewMode: .sourceAccurate)).map(\.text)
            == Array(expected.tokens(viewMode: .sourceAccurate)).map(\.text)
    }
    guard matches(actual("initialOutcomes"), expected: """
        public func initialOutcomes() throws -> SwiftTLA.InitialEvaluationOutcomes<Machine> {
            return try \(modelName).initialOutcomes(\(arguments))
        }
        """), matches(actual("runValidation", firstParameter: "initialOutcomes"), expected: """
        public func runValidation(initialOutcomes: SwiftTLA.InitialEvaluationOutcomes<Machine>, maximumStates: \(nativeIntType),
            checking: ModelChecks<Property>, stopOnViolation: \(nativeBoolType), stopOnReachability: \(nativeBoolType),
            fairness: [MachineFairnessCondition<Machine.Snapshot, Machine.Action>] = [],
            emit: (MachineValidationEvent<Machine>) throws -> Void) throws -> MachineValidationSummary<Property> {
            switch selectedView {
            case nil:
                return try MachineValidator.run(initialOutcomes: initialOutcomes, maximumStates: maximumStates,
                    checking: checking, stopOnViolation: stopOnViolation,
                    stopOnReachability: stopOnReachability, fairness: fairness, emit: emit)
            default: throw ExplorationError.configurationMismatch
            }
        }
        """) else { throw mismatch() }

    func selectionMismatch() -> CompilationDiagnostic {
        CompilationDiagnostic(code: .unsupportedGeneratedValueShape, stage: .validation,
            path: "native.validation.checkingSelection",
            expected: "the compiled scenario's selected properties and deadlock setting in both output routes",
            actual: "the generated scenario changes a check selection or its formal projection",
            nextSafeAction: "Report this generated validation translation failure.")
    }
    guard matches(actual("render"), expected: """
        public func render() throws -> RenderedSpecification {
            try \(modelName).render(\(arguments)).selectingChecks(checking,
                formalPropertyNames: Machine.formalPropertyNames, behavior: behavior,
                symmetry: selectedSymmetry, fairnessProfile: selectedFairnessProfileName,
                view: selectedView.map { "__SwiftTLAView\\($0)" },
                postcondition: postconditionName)
        }
        """) else { throw selectionMismatch() }

    let constructors = declarations.compactMap { $0.as(FunctionDeclSyntax.self) }
        .filter { $0.name.text == "validationScenarios" }
    guard constructors.count == 1, let body = constructors.first?.body,
          body.statements.count == 1, let statement = body.statements.first,
          let values = (statement.item.as(ExprSyntax.self)
              ?? statement.item.as(ReturnStmtSyntax.self)?.expression)?.as(ArrayExprSyntax.self),
          values.elements.count == model.program.behavior.validationScenarios.count else {
        throw selectionMismatch()
    }
    let properties = model.program.layout.properties
    let identifiers = GeneratedMachineAPI.generatedIdentifiers(
        properties.map { $0.declaration.name }, fallback: "property").map {
            $0.hasPrefix("`") ? String($0.dropFirst().dropLast()) : $0
        }
    let names = Dictionary(uniqueKeysWithValues: zip(properties.map(\.id), identifiers))
    for (element, scenario) in zip(values.elements, model.program.behavior.validationScenarios) {
        guard let constructor = element.expression.as(FunctionCallExprSyntax.self),
              constructor.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "ValidationScenario"
        else { throw selectionMismatch() }
        let selections = constructor.arguments.filter { $0.label?.text == "checking" }
        guard selections.count == 1,
              let call = selections.first?.expression.as(FunctionCallExprSyntax.self),
              call.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.text == "ModelChecks",
              call.arguments.count == 2,
              let propertyList = call.arguments.first(where: { $0.label?.text == "properties" })?
                .expression.as(ArrayExprSyntax.self),
              let deadlock = call.arguments.first(where: { $0.label?.text == "checkDeadlock" })?
                .expression.as(BooleanLiteralExprSyntax.self),
              deadlock.literal.text == (scenario.checkDeadlock ? "true" : "false") else {
            throw selectionMismatch()
        }
        var selected: Set<String> = []
        for property in propertyList.elements {
            guard let member = property.expression.as(MemberAccessExprSyntax.self), member.base == nil else {
                throw selectionMismatch()
            }
            selected.insert(member.declName.baseName.sourceIdentifierName)
        }
        var expected: Set<String> = []
        for property in scenario.checks {
            guard let name = names[property] else { throw selectionMismatch() }
            expected.insert(name)
        }
        guard selected == expected else { throw selectionMismatch() }
    }
}
