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
                let collectionArguments = machineArguments.isEmpty ? "" : ", " + machineArguments
                var values: [String] = []
                for (offset, query) in refinement.variableMappings.enumerated() {
                    let enabled = enabledActionsCall(query.enabledActions, state: "state", collectionArguments: collectionArguments)
                    let type = try swiftType(query.expression.resultType)
                    let value = try expression(query.expression)
                    if query.enabledActions.isEmpty {
                        values.append("let value\(offset): \(type) = \(value)")
                    } else {
                        values.append("""
                        let value\(offset): \(type) = try { () throws -> \(type) in
                            let enabled: Set<Int> = \(enabled)
                            return \(value)
                        }()
                        """)
                    }
                }
                let arguments = abstractModel.api.variables.enumerated().map {
                    "\($0.element.swiftIdentifier): value\($0.offset)"
                }.joined(separator: ", ")
                declarations += try nativeDeclarations("""
                private func _mapRefinement\(index)(_ state: Snapshot) throws -> \(name) {
                    \(values.joined(separator: "\n"))
                    return \(name)._mapped(.init(\(arguments)))
                }
                """)
                checks.append("""
                if let failure = try graph.refinementFailure(initialMachines: \(name).initialMachines(), mapping: _mapRefinement\(index)) {
                    failures[\(String(reflecting: refinement.name))] = failure
                }
                """)
            }
        }
        let body = checks.isEmpty ? "return [:]" : "var failures: [String: RefinementFailure<Snapshot, Action>] = [:]\n" + checks.joined(separator: "\n") + "\nreturn failures"
        declarations += try nativeDeclarations("""
        public func refinementFailures(in graph: inout ReachabilityGraph<Self>) throws -> [String: RefinementFailure<Snapshot, Action>] {
            \(body)
        }
        """)
        return declarations
    }
}
