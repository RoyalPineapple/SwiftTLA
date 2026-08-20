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
        let labelField = hasActions ? "public let label: ActionLabel" : ""
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
        let typedApply = hasActions ? """
            public \(modifier)func apply(_ action: ActionLabel) throws -> TransitionResult {
                try _apply(action)
            }
            """ : ""
        let observation = hasActions ? """
            public struct MachineObservation: Sendable, Equatable {
                public let state: State
                public let availableActions: [ActionLabel]
            }
            """ : ""
        let availableActions = hasActions ? """
            public func availableActions() throws -> [ActionLabel] {
                try _actionExecutor().availableLabels(in: _stateWithLiveCollections()).filter {
                    !Self._identityRoutedActionOrdinals.contains(Self._actionOrdinal(for: $0))
                }
            }
            """ : ""
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
        return [
            DeclSyntax(stringLiteral: """
            public struct TransitionResult: Sendable, Equatable {
                \(labelField.replacingOccurrences(of: "label", with: "action"))
                public let before: State
                public let after: State
            }
            """),
            DeclSyntax(stringLiteral: observation),
            DeclSyntax(stringLiteral: """
            public var state: State {
                _machine.snapshot
            }
            """),
            DeclSyntax(stringLiteral: "private static let _identityRoutedActionOrdinals: Set<Int> = [\(identityRoutedOrdinals)]"),
            DeclSyntax(stringLiteral: """
            private func _stateWithLiveCollections() throws -> TLAStateProjection {
                \(stateWithLiveCollections)
            }
            """),
            DeclSyntax(stringLiteral: availableActions),
            DeclSyntax(stringLiteral: typedApply),
            DeclSyntax(stringLiteral: """
            private \(modifier)func _apply(_ action: ActionLabel) throws -> TransitionResult {
                \(identityRoutedGuard)
                let evidence = try _machine.apply(
                    action,
                    using: _actionExecutor(),
                    from: _stateWithLiveCollections()
                ) { _ in true }
                return TransitionResult(
                    action: evidence.action,
                    before: evidence.before,
                    after: evidence.after
                )
            }
            """),
            DeclSyntax(stringLiteral: hasActions ? """
            public func synchronousMachineObservation() throws -> MachineObservation {
                .init(state: state, availableActions: try availableActions())
            }
            """ : ""),
            DeclSyntax(stringLiteral: hasActions ? """
            public func machineObservation() async throws -> MachineObservation {
                try synchronousMachineObservation()
            }
            """ : ""),
        ]
    }
}
