import SwiftSyntax
import SwiftTLA

extension NativeSwiftEmitter {
    func supportsNativeRefinement(_ refinement: CompiledRefinementProgram) -> Bool {
        let abstract = refinement.abstract
        return abstract.layout.parameters.isEmpty
            && abstract.layout.variables.allSatisfy { $0.declaration.origin == .source && $0.collection == nil }
    }

    mutating func refinementDeclarations(nested: Bool) throws -> [DeclSyntax] {
        var declarations: [DeclSyntax] = []
        var checks: [String] = []
        let unsupported = program.refinements.filter { !supportsNativeRefinement($0) }.map { refinement in
            "if checking.contains(.\(propertyCases[refinement.id]!)) { throw ExplorationError.unsupportedRefinement(\(String(reflecting: propertyCases[refinement.id]!))) }"
        }
        if !nested {
            for (index, refinement) in program.refinements.enumerated() where supportsNativeRefinement(refinement) {
                let name = "_Refinement\(index)"
                let abstractModel = try MacroCompilation(typeName: name, program: refinement.abstract)
                var abstractEmitter = NativeSwiftEmitter(model: abstractModel, sharedTypes: typeDeclarations)
                let members = try abstractEmitter.machineMembers(nested: true).map(\.description).joined(separator: "\n")
                declarations += try nativeDeclarations("""
                @_documentation(visibility: internal)
                public struct \(name): StateMachine {
                    \(members)
                    fileprivate static func _mapped(_ state: State) -> Self {
                        Self(execution: Snapshot(state: state))
                    }
                }
                """)
                var values: [String] = []
                for (offset, query) in refinement.variableMappings.enumerated() {
                    let type = try swiftType(query.expression.resultType)
                    let value = try expression(query.expression)
                    values.append("let value\(offset): \(type) = \(value)")
                }
                let arguments = abstractModel.api.variables.enumerated().map {
                    "\($0.element.argumentLabel): value\($0.offset)"
                }.joined(separator: ", ")
                declarations += try nativeDeclarations("""
                private func _mapRefinement\(index)(_ state: Snapshot) throws -> \(name) {
                    \(values.joined(separator: "\n"))
                    return \(name)._mapped(.init(\(arguments)))
                }
                """)
                checks.append("""
                if checking.contains(.\(propertyCases[refinement.id]!)), let failure = try graph.refinementFailure(initialMachines: \(name).initialMachines(), mapping: _mapRefinement\(index)) {
                    failures[.\(propertyCases[refinement.id]!)] = failure
                }
                """)
            }
        }
        let body = checks.isEmpty
            ? unsupported.joined(separator: "\n") + "\nreturn [:]"
            : "var failures: [Property: RefinementFailure<Snapshot, Action>] = [:]\n"
                + (checks + unsupported).joined(separator: "\n") + "\nreturn failures"
        declarations += try nativeDeclarations("""
        public static var refinementProperties: [Property] { [\(program.refinements.map { ".\(propertyCases[$0.id]!)" }.joined(separator: ", "))] }
        public func refinementFailures(in graph: inout ReachabilityGraph<Self>, checking: Set<Property> = Set(Property.allCases)) throws -> [Property: RefinementFailure<Snapshot, Action>] {
            \(body)
        }
        public func validationRefinementFailures(in graph: inout MachineValidationGraph<Self>, checking: Set<Property> = Set(Property.allCases)) throws -> [Property: RefinementFailure<Snapshot, Action>] {
            \(body)
        }
        """)
        return declarations
    }
}
