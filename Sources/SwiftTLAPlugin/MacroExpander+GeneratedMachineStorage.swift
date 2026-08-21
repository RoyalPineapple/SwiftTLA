import SwiftSyntax
import SwiftTLA

extension MacroExpander {
    static func generateGeneratedMachineStorageMembers(
        isActor: Bool,
        hasActions: Bool,
        actions: [MachineSurfacePlan.Action],
        variables: [MachineSurfacePlan.Variable],
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
        let liveProjection = symmetricCollections.compactMap { collection in
            guard let ordinal = variables.firstIndex(where: { $0.formalName == collection.formalName }) else {
                return nil
            }
            """
            state = try _storage.replacing(
                formalValue: \(collection.formalName).projection().modelValue,
                at: \(ordinal),
                in: state
            )
            """
        }.joined(separator: "\n                ")
        let stateWithLiveCollections = symmetricCollections.isEmpty
            ? "_storageState"
            : """
            var state = _storageState
                            \(liveProjection)
                            return state
            """
        var members: [DeclSyntax] = [
            DeclSyntax(stringLiteral: """
            public var state: State {
                _state
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
                private func _stateWithLiveCollections() throws -> GeneratedMachineStorage.State {
                    \(stateWithLiveCollections)
                }
                """),
                DeclSyntax(stringLiteral: """
                public func availableActions() throws -> [ActionLabel] {
                    try _storage.availableActions(in: _stateWithLiveCollections()) { ordinal, arguments in
                        guard let action = Self._actionLabel(
                            actionAt: ordinal,
                            arguments: arguments
                        ) else {
                            throw GeneratedMachineError.noMatchingSuccessor
                        }
                        return action
                    }.filter { !Self._identityRoutedActionOrdinals.contains(Self._actionOrdinal(for: $0)) }
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
                let before = _state
                let afterStorageState = try _storage.apply(
                    actionOrdinal: Self._actionOrdinal(for: action),
                    formalArguments: Self._formalArguments(for: action),
                    from: _stateWithLiveCollections()
                )
                let after = try State(storage: _storage, storageState: afterStorageState)
                _storageState = afterStorageState
                _state = after
                return TransitionResult(
                    action: action,
                    before: before,
                    after: after
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
