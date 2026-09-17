import SwiftSyntax
import SwiftTLA

extension NativeSwiftEmitter {
    mutating func exportDeclarations() throws -> [DeclSyntax] {
        let parameters = program.layout.parameters.isEmpty ? "" : "configuration: Configuration"
        let body: String
        do {
            let module = try program.renderModule()
            let plusCal: String
            do {
                plusCal = try program.renderAuthoredPlusCal(declarations: module).map {
                    ".success(\(String(reflecting: $0)))"
                } ?? "nil"
            } catch let diagnostic as CompilationDiagnostic {
                plusCal = ".failure(\(exportDiagnostic(diagnostic)))"
            }
            let parameterBindings = try program.layout.parameters.map { parameter in
                guard let type = program.bindingTypes[parameter.binder],
                      let name = program.binderNames[parameter.binder] else {
                    throw unsupported("unresolved export parameter: \(parameter.reference.name)")
                }
                let value = try formalValue("configuration.`\(parameter.reference.name)`", type: type)
                return "\(String(reflecting: "CONSTANT " + name + " = ")) + (\(value)).description"
            }
            let declarations = module.configuration.declarations.map { String(reflecting: $0) } + parameterBindings
            let imports = try module.imports.map { imported in
                guard let owner = module.importedOwnership.first(where: { $0.moduleName == imported.name }) else {
                    throw unsupported("missing imported module ownership: \(imported.name)")
                }
                return "(name: \(String(reflecting: imported.name)), source: \(String(reflecting: imported.tla)), structuralPath: \(String(reflecting: owner.structuralPath)))"
            }.joined(separator: ",\n")
            let dependencies = module.dependencies.map {
                "(importingModule: \(String(reflecting: $0.importingModule)), importedModule: \(String(reflecting: $0.importedModule)), structuralPath: \(String(reflecting: $0.structuralPath)))"
            }.joined(separator: ",\n")
            let actions = module.renderedActions.map { action in
                "RenderedAction(sourceName: \(String(reflecting: action.sourceName)), arguments: [\(action.arguments.map(renderedLiteral).joined(separator: ", "))], renderedName: \(String(reflecting: action.renderedName)))"
            }
            var actionMetadata = "\(module.symbolicActions.isEmpty ? "let" : "var") _actions: [RenderedAction] = [\(actions.joined(separator: ", "))]"
            for id in module.symbolicActions {
                let action = program[id]
                var loops: [String] = []
                var arguments: [String] = []
                for binding in action.bindings {
                    try program.requireImmutableDomain(binding.domain,
                        path: "export.actions.\(program.layout.actions[id.ordinal].renderedName).\(binding.sourceName).domain")
                    loops.append("for \(binder(binding.binder)) in \(try actionDomain(binding, state: "")) {")
                    arguments.append(try formalValue(binder(binding.binder), type: program.bindingTypes[binding.binder]!))
                }
                let name = String(reflecting: program.layout.actions[id.ordinal].renderedName)
                actionMetadata += "\n" + loops.joined(separator: "\n") + "\n" + """
                let _arguments: [TLAValue] = [\(arguments.joined(separator: ", "))]
                _actions.append(RenderedAction(sourceName: \(name), arguments: _arguments,
                    renderedName: FormalActionCall(name: \(name), arguments: _arguments).description))
                """ + String(repeating: "\n}", count: loops.count)
            }
            var obligationMetadata = "var _obligations: [String: [_RenderedTemporalObligation]] = [:]"
            for property in program.behavior.temporalProperties {
                guard let obligations = module.temporalObligations[property.id] else { continue }
                var loops: [String] = []
                var substitutions: [String] = []
                for binding in property.bindings {
                    try program.requireImmutableDomain(binding.domain, path: "export.properties.\(property.name).domain")
                    guard let name = module.temporalBindingNames[binding.binder],
                          let type = program.bindingTypes[binding.binder] else {
                        throw unsupported("unresolved temporal export binding: \(binding.sourceName)")
                    }
                    loops.append("for \(binder(binding.binder)) in \(try actionDomain(binding, state: "")) {")
                    let value = try formalValue(binder(binding.binder), type: type)
                    substitutions.append("\(String(reflecting: "LET " + name + " == ")) + (\(value)).description + \(String(reflecting: " IN "))")
                }
                let prefix = substitutions.isEmpty ? "\"\"" : substitutions.joined(separator: " + ")
                obligationMetadata += "\n" + loops.joined(separator: "\n")
                for obligation in obligations {
                    obligationMetadata += """

                    _obligations[\(String(reflecting: property.name)), default: []].append(
                        _RenderedTemporalObligation(initialCondition: \(prefix) + \(String(reflecting: obligation.initialCondition)),
                            property: \(prefix) + \(String(reflecting: obligation.property))))
                    """
                }
                obligationMetadata += String(repeating: "\n}", count: loops.count)
            }
            if module.temporalObligations.isEmpty {
                obligationMetadata = "let _obligations: [String: [_RenderedTemporalObligation]] = [:]"
            }
            body = """
            \(actionMetadata)
            \(obligationMetadata)
            return try RenderedSpecification(_generatedModule: \(String(reflecting: program.moduleName)),
                source: \(String(reflecting: module.renderedModuleSource)),
                compilationIdentity: \(String(reflecting: program.identity.value)),
                declarations: [\(declarations.joined(separator: ", "))],
                checkDeadlock: \(module.configuration.checkDeadlock),
                invariants: \(String(reflecting: module.configuration.invariants)),
                reachabilityProperties: \(String(reflecting: module.configuration.reachabilityProperties)),
                properties: \(String(reflecting: module.configuration.properties)),
                refinements: \(String(reflecting: module.configuration.refinements)),
                symmetry: \(String(reflecting: module.configuration.symmetry)),
                actions: _actions, _generatedPlusCal: \(plusCal),
                _generatedImports: [\(imports)], _generatedDependencies: [\(dependencies)],
                _generatedTemporalObligations: _obligations)
            """
        } catch let diagnostic as CompilationDiagnostic {
            body = """
            throw \(exportDiagnostic(diagnostic))
            """
        }
        return try nativeDeclarations("""
        public static func render(\(parameters)) throws -> RenderedSpecification {
            \(body)
        }
        """)
    }

    private func exportDiagnostic(_ diagnostic: CompilationDiagnostic) -> String {
        """
        CompilationDiagnostic(code: .\(diagnostic.code), stage: .\(diagnostic.stage),
            path: \(String(reflecting: diagnostic.path)), expected: \(String(reflecting: diagnostic.expected)),
            actual: \(String(reflecting: diagnostic.actual)), nextSafeAction: \(String(reflecting: diagnostic.nextSafeAction)))
        """
    }
}
