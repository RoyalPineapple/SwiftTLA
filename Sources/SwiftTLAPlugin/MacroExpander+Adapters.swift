import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftTLA

enum NestedAdapterKind {
    case actor
    case observable
}

extension MacroExpander {
    static func generateNestedAdapterMembers(
        kind: NestedAdapterKind,
        canonicalModel: ParsedMacroModel,
        needsPublicInitializer: Bool
    ) -> [DeclSyntax] {
        let modelType = canonicalModel.typeName
        let isolation = kind == .observable ? "@MainActor " : ""
        let canonicalStorage = kind == .observable
            ? "@MainActor private var _canonical: \(modelType)"
            : "private var _canonical = \(modelType)()"
        var declarations: [DeclSyntax] = [
            DeclSyntax(stringLiteral: "public typealias CanonicalModel = \(modelType)"),
            DeclSyntax(stringLiteral: "public typealias State = \(modelType).State"),
            DeclSyntax(stringLiteral: "public typealias Variables = \(modelType).Variables"),
            DeclSyntax(stringLiteral: "public typealias ActionLabel = \(modelType).ActionLabel"),
            DeclSyntax(stringLiteral: "public typealias TransitionResult = \(modelType).TransitionResult"),
            DeclSyntax(stringLiteral: canonicalStorage),
            DeclSyntax(stringLiteral: """
            \(isolation)public func withCanonicalMachine<Result: Sendable>(
                _ operation: @escaping @Sendable (inout \(modelType)) throws -> Result
            ) async rethrows -> Result {
                try operation(&_canonical)
            }
            """)
        ]
        if kind == .observable {
            if needsPublicInitializer {
                declarations.append(DeclSyntax(stringLiteral: """
                @MainActor public init() {
                    _canonical = \(modelType)()
                }
                """))
            }
            declarations.append(contentsOf: generateNestedObservableMembers(model: canonicalModel))
        } else {
            if needsPublicInitializer {
                declarations.append(DeclSyntax(stringLiteral: """
                public init() {}
                """))
            }
            declarations.append(DeclSyntax(stringLiteral: """
            public var state: State {
                get async {
                    await withCanonicalMachine { canonical in
                        canonical.state
                    }
                }
            }
            public func tlaSnapshot() async -> TLAStateProjectionResult {
                await withCanonicalMachine { canonical in
                    canonical.tlaSnapshot()
                }
            }
            """))
        }
        return declarations
    }

    static func generateNestedObservableMembers(model: ParsedMacroModel) -> [DeclSyntax] {
        let callbacks = model.actions.map { action in
            let callbackName = "on" + action.name.prefix(1).capitalized + action.name.dropFirst()
            let parameterTypes = publicBindings(for: action).map { swiftType(for: action, binding: $0) }
            let parameters = (parameterTypes + ["State", "State"]).joined(separator: ", ")
            return DeclSyntax(stringLiteral: "@MainActor public var \(callbackName): ((\(parameters)) async -> Void)?")
        }
        let notifications = model.actions.map { action -> String in
            let callbackName = "on" + action.name.prefix(1).capitalized + action.name.dropFirst()
            let publicBindings = publicBindings(for: action)
            let pattern: String
            let arguments: String
            if publicBindings.isEmpty {
                pattern = ".\(action.name)"
                arguments = "evidence.before, evidence.after"
            } else {
                let names = publicBindings.map(\.name)
                pattern = ".\(action.name)(\(names.map { "let \($0)" }.joined(separator: ", ")))"
                arguments = (names + ["evidence.before", "evidence.after"]).joined(separator: ", ")
            }
            return """
                case \(pattern):
                    if let \(callbackName) {
                        await \(callbackName)(\(arguments))
                    }
            """
        }.joined(separator: "\n")
        let typedActions = model.actions.map { action -> DeclSyntax in
            let bindings = publicBindings(for: action)
            let parameters = bindings.map { binding in
                "\(binding.name): \(swiftType(for: action, binding: binding))"
            }.joined(separator: ", ")
            let labelArguments = bindings.map { "\($0.name): \($0.name)" }.joined(separator: ", ")
            let label = bindings.isEmpty
                ? "ActionLabel.\(action.name).toInvocation()"
                : "ActionLabel.\(action.name)(\(labelArguments)).toInvocation()"
            return DeclSyntax(stringLiteral: """
            @MainActor public func _\(action.name)(\(parameters)) async throws -> TransitionResult {
                try await execute(\(label))
            }
            """)
        }
        return callbacks + [
            DeclSyntax(stringLiteral: """
            @MainActor public var state: State {
                _canonical.state
            }
            """),
            DeclSyntax(stringLiteral: """
            @MainActor public func machineObservation() async -> TLAMachineObservation {
                await withCanonicalMachine { canonical in
                    canonical.synchronousMachineObservation()
                }
            }
            @MainActor public func tlaSnapshot() -> TLAStateProjectionResult {
                _canonical.tlaSnapshot()
            }
            """),
            DeclSyntax(stringLiteral: """
            @MainActor public func execute(_ invocation: TLAActionInvocation) async throws -> TransitionResult {
                let evidence = try await withCanonicalMachine { canonical in
                    try canonical.executeSynchronously(invocation)
                }
                switch evidence.action {
                \(notifications)
                }
                return evidence
            }
            """)
        ] + typedActions
    }
}
