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
        canonicalModel: MacroCompilation,
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
            DeclSyntax(stringLiteral: "public typealias TransitionResult = \(modelType).TransitionResult"),
            DeclSyntax(stringLiteral: "public static var machineSchema: MachineSchema { CanonicalModel.machineSchema }"),
            DeclSyntax(stringLiteral: "public static var generatedMachineMetadata: GeneratedMachineMetadata { CanonicalModel.generatedMachineMetadata }"),
            DeclSyntax(stringLiteral: "public static func verifyGeneratedMachineContract(metadata: GeneratedMachineMetadata? = nil, verificationStateLimit: Int? = nil) -> GeneratedMachineContractReport { CanonicalModel.verifyGeneratedMachineContract(metadata: metadata, verificationStateLimit: verificationStateLimit) }"),
            DeclSyntax(stringLiteral: canonicalStorage),
            DeclSyntax(stringLiteral: """
            \(isolation)public func withCanonicalMachine<Result: Sendable>(
                _ operation: @escaping @Sendable (inout \(modelType)) throws -> Result
            ) async rethrows -> Result {
                try operation(&_canonical)
            }
            """)
        ]
        if !canonicalModel.machineSurface.actions.isEmpty {
            declarations.insert(3, DeclSyntax(stringLiteral: "public typealias ActionLabel = \(modelType).ActionLabel"))
        }
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

    static func generateNestedObservableMembers(model: MacroCompilation) -> [DeclSyntax] {
        let actions = model.machineSurface.actions
        let callbacks = actions.map { action in
            let identifier = action.swiftIdentifier
            let callbackName = "on" + identifier.prefix(1).capitalized + identifier.dropFirst()
            let parameterTypes = action.bindings.filter(\.isPublic).map(\.swiftType)
            let parameters = (parameterTypes + ["State", "State"]).joined(separator: ", ")
            return DeclSyntax(stringLiteral: "@MainActor public var \(callbackName): ((\(parameters)) async -> Void)?")
        }
        let notifications = actions.map { action -> String in
            let identifier = action.swiftIdentifier
            let callbackName = "on" + identifier.prefix(1).capitalized + identifier.dropFirst()
            let publicBindings = action.bindings.filter(\.isPublic)
            let pattern: String
            let arguments: String
            if publicBindings.isEmpty {
                pattern = ".\(identifier)"
                arguments = "evidence.before, evidence.after"
            } else {
                let names = publicBindings.map(\.formalName)
                pattern = ".\(identifier)(\(names.map { "let \($0)" }.joined(separator: ", ")))"
                arguments = (names + ["evidence.before", "evidence.after"]).joined(separator: ", ")
            }
            return """
                case \(pattern):
                    if let \(callbackName) {
                        await \(callbackName)(\(arguments))
                    }
            """
        }.joined(separator: "\n")
        let typedActions = actions.map { action -> DeclSyntax in
            let identifier = action.swiftIdentifier
            let bindings = action.bindings.filter(\.isPublic)
            let parameters = bindings.map { binding in
                "\(binding.formalName): \(binding.swiftType)"
            }.joined(separator: ", ")
            let labelArguments = bindings.map { "\($0.formalName): \($0.formalName)" }.joined(separator: ", ")
            let label = bindings.isEmpty
                ? "ActionLabel.\(identifier).toInvocation()"
                : "ActionLabel.\(identifier)(\(labelArguments)).toInvocation()"
            return DeclSyntax(stringLiteral: """
            @MainActor public func _\(identifier)(\(parameters)) async throws -> TransitionResult {
                try await execute(\(label))
            }
            """)
        }
        var declarations = callbacks + [
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
        ]
        let executeBody: String
        if actions.isEmpty {
            executeBody = """
            @MainActor public func execute(_ invocation: TLAActionInvocation) async throws -> TransitionResult {
                try await withCanonicalMachine { canonical in
                    try canonical.executeSynchronously(invocation)
                }
            }
            """
        } else {
            executeBody = """
            @MainActor public func execute(_ invocation: TLAActionInvocation) async throws -> TransitionResult {
                let evidence = try await withCanonicalMachine { canonical in
                    try canonical.executeSynchronously(invocation)
                }
                switch evidence.action {
                \(notifications)
                }
                return evidence
            }
            """
        }
        declarations.append(DeclSyntax(stringLiteral: executeBody))
        return declarations + typedActions
    }
}
