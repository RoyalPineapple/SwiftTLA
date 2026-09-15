import SwiftSyntax
import SwiftTLA

extension NativeSwiftEmitter {
    func exportDeclarations() throws -> [DeclSyntax] {
        let parameters = program.layout.parameters.isEmpty ? "" : "configuration: Configuration"
        let body: String
        do {
            let module = try program.renderModule()
            let parameterBindings = try program.layout.parameters.map { parameter in
                guard let type = program.bindingTypes[parameter.binder],
                      let name = program.binderNames[parameter.binder] else {
                    throw unsupported("unresolved export parameter: \(parameter.reference.name)")
                }
                let value = try formalValue("configuration.`\(parameter.reference.name)`", type: type)
                return "\(String(reflecting: "CONSTANT " + name + " = ")) + (\(value)).description"
            }
            let declarations = module.configuration.declarations.map { String(reflecting: $0) } + parameterBindings
            let actions = module.renderedActions.map { action in
                "RenderedAction(sourceName: \(String(reflecting: action.sourceName)), arguments: [\(action.arguments.map(renderedLiteral).joined(separator: ", "))], renderedName: \(String(reflecting: action.renderedName)))"
            }
            body = """
            return try RenderedSpecification(_generatedModule: \(String(reflecting: program.moduleName)),
                source: \(String(reflecting: module.renderedModuleSource)),
                compilationIdentity: \(String(reflecting: program.identity.value)),
                declarations: [\(declarations.joined(separator: ", "))],
                checkDeadlock: \(module.configuration.checkDeadlock),
                invariants: \(String(reflecting: module.configuration.invariants)),
                reachabilityProperties: \(String(reflecting: module.configuration.reachabilityProperties)),
                properties: \(String(reflecting: module.configuration.properties)),
                symmetry: \(String(reflecting: module.configuration.symmetry)),
                actions: [\(actions.joined(separator: ", "))])
            """
        } catch let diagnostic as CompilationDiagnostic {
            body = """
            throw CompilationDiagnostic(code: .\(diagnostic.code), stage: .\(diagnostic.stage),
                path: \(String(reflecting: diagnostic.path)), expected: \(String(reflecting: diagnostic.expected)),
                actual: \(String(reflecting: diagnostic.actual)), nextSafeAction: \(String(reflecting: diagnostic.nextSafeAction)))
            """
        }
        return try nativeDeclarations("""
        public static func render(\(parameters)) throws -> RenderedSpecification {
            \(body)
        }
        """)
    }
}
