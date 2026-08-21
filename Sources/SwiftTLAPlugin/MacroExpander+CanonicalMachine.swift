import SwiftSyntax
import SwiftTLA

extension MacroExpander {
    static func generateCanonicalMachineMembers(
        isActor: Bool,
        hasActions: Bool,
        actions: [MachineSurfacePlan.Action],
        symmetricCollections: [MachineSurfacePlan.SymmetricCollection] = [],
        identityRoutedActions: Set<String> = []
    ) -> [DeclSyntax] {
        let modifier = isActor ? "" : "mutating "
        let identityRoutedOrdinals = identityRoutedActions.isEmpty
            ? ""
            : identityRoutedActions.sorted().compactMap { name in
                actions.firstIndex { $0.formalName == name }.map(String.init)
            }.joined(separator: ", ")
        let identityRoutedGuard = identityRoutedActions.isEmpty
            ? ""
            : """
                guard !Self._identityRoutedActionOrdinals.contains(Self._actionOrdinal(for: action)) else {
                    throw GeneratedMachineError.identityRoutedActionRequiresID
                }
            """
        let liveProjection = symmetricCollections.map {
            """
            guard let token = TLAStateProjection.Token(validating: \(String(reflecting: $0.formalName))) else {
                throw TLAStateProjectionDiagnostic.invalidKey(path: \(String(reflecting: $0.formalName)))
            }
            state = try state.replacing(\($0.formalName).projection().modelValue, for: token)
            """
        }.joined(separator: "\n                ")
        let stateWithLiveCollections = symmetricCollections.isEmpty
            ? "try _machine.stateProjection().requireProjection()"
            : """
            var state = try _machine.stateProjection().requireProjection()
                            \(liveProjection)
                            return state
            """
        var members: [DeclSyntax] = [
            DeclSyntax(stringLiteral: """
            public var state: State {
                _machine.snapshot
            }
            """),
            DeclSyntax(stringLiteral: """
            public struct TransitionResult: Sendable, Equatable {
                public let action: ActionLabel
                public let before: State
                public let after: State
            }
            """),
        ]
        if hasActions {
            members += [
                DeclSyntax(stringLiteral: """
                public struct MachineObservation: Sendable, Equatable {
                    public let state: State
                    public let availableActions: [ActionLabel]
                }
                """),
                DeclSyntax(stringLiteral: "private static let _identityRoutedActionOrdinals: Set<Int> = [\(identityRoutedOrdinals)]"),
                DeclSyntax(stringLiteral: """
                private func _stateWithLiveCollections() throws -> TLAStateProjection {
                    \(stateWithLiveCollections)
                }
                """),
                DeclSyntax(stringLiteral: """
                public func availableActions() throws -> [ActionLabel] {
                    try _machine.availableActions(in: _stateWithLiveCollections()).filter {
                        !Self._identityRoutedActionOrdinals.contains(Self._actionOrdinal(for: $0))
                    }
                }
                """),
                DeclSyntax(stringLiteral: """
                public \(modifier)func apply(_ action: ActionLabel) throws -> TransitionResult {
                    try _apply(action)
                }
                """),
                DeclSyntax(stringLiteral: """
            private \(modifier)func _apply(_ action: ActionLabel) throws -> TransitionResult {
                \(identityRoutedGuard)
                let evidence = try _machine.apply(
                    action,
                    from: _stateWithLiveCollections()
                ) { _ in true }
                return TransitionResult(
                    action: evidence.action,
                    before: evidence.before,
                    after: evidence.after
                )
            }
            """),
                DeclSyntax(stringLiteral: """
                public func synchronousMachineObservation() throws -> MachineObservation {
                    .init(state: state, availableActions: try availableActions())
                }
                """),
                DeclSyntax(stringLiteral: """
                public func machineObservation() async throws -> MachineObservation {
                    try synchronousMachineObservation()
                }
                """),
            ]
        }
        return members
    }
}
