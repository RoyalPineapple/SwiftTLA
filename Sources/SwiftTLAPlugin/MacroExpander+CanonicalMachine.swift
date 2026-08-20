import SwiftSyntax
import SwiftTLA

extension MacroExpander {
    static func generateCanonicalMachineMembers(
        isActor: Bool,
        hasActions: Bool,
        symmetricCollections: [MachineSurfacePlan.SymmetricCollection] = [],
        identityRoutedActions: Set<String> = []
    ) -> [DeclSyntax] {
        let modifier = isActor ? "" : "mutating "
        let labelField = hasActions ? "public let label: ActionLabel" : ""
        let labelValidation = hasActions ? """
                guard let label = Self._actionLabel(for: invocation) else {
                    throw GeneratedMachineError.unrepresentableActionLabel(invocation)
                }
        """ : ""
        let labelArgument = hasActions ? "label: label," : ""
        let identityRoutedNames = identityRoutedActions.sorted().map { "\"\($0)\"" }.joined(separator: ", ")
        let invocationFilter = identityRoutedActions.isEmpty
            ? ""
            : ".filter { !_identityRoutedActionNames.contains($0.name) }"
        let invocationGuard = identityRoutedActions.isEmpty
            ? ""
            : """
                guard !_identityRoutedActionNames.contains(invocation.name) else {
                    throw GeneratedMachineError.identityRoutedActionRequiresID(invocation)
                }
            """
        let typedApply = hasActions ? """
            public \(modifier)func apply(_ action: ActionLabel) throws -> TransitionResult {
                try _apply(Self._actionInvocation(for: action))
            }
            """ : ""
        let availableActions = hasActions ? """
            public func availableActions() throws -> [ActionLabel] {
                try _machine.availableInvocations(in: _stateWithLiveCollections())\(invocationFilter).map { invocation in
                    guard let label = Self._actionLabel(for: invocation) else {
                        throw GeneratedMachineError.unrepresentableActionLabel(invocation)
                    }
                    return label
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
            DeclSyntax(stringLiteral: """
            public var state: State {
                _machine.snapshot
            }
            """),
            DeclSyntax(stringLiteral: "private static let _identityRoutedActionNames: Set<String> = [\(identityRoutedNames)]"),
            DeclSyntax(stringLiteral: """
            private func _stateWithLiveCollections() throws -> TLAStateProjection {
                \(stateWithLiveCollections)
            }
            """),
            DeclSyntax(stringLiteral: """
            public func tlaSnapshot() -> TLAStateProjectionResult {
                do {
                    return .projected(try _stateWithLiveCollections())
                } catch let diagnostic as TLAStateProjectionDiagnostic {
                    return .unavailable(diagnostic)
                } catch {
                    return .unavailable(.invalidKey(path: "state"))
                }
            }
            """),
            DeclSyntax(stringLiteral: availableActions),
            DeclSyntax(stringLiteral: typedApply),
            DeclSyntax(stringLiteral: """
            private \(modifier)func _apply(_ invocation: TLAActionInvocation) throws -> TransitionResult {
                \(invocationGuard)
                \(labelValidation)
                let evidence = try _machine.apply(invocation, from: _stateWithLiveCollections()) { _ in true }
                return TransitionResult(
                    \(labelArgument.replacingOccurrences(of: "label:", with: "action:"))
                    before: evidence.before,
                    after: evidence.after
                )
            }
            """),
            DeclSyntax(stringLiteral: """
            public func synchronousMachineObservation() -> TLAMachineObservation {
                let state = tlaSnapshot()
                guard let projection = state.projection else {
                    let diagnostic = state.diagnostic ?? .invalidKey(path: "state")
                    return .init(
                        state: state,
                        availability: .unavailable(.init(
                            code: .stateProjectionFailed,
                            message: diagnostic.description,
                            projectionDiagnostic: diagnostic
                        ))
                    )
                }
                do {
                    return .init(state: state, availability: .available(try _machine.availableInvocations(in: projection)\(invocationFilter)))
                } catch {
                    return .init(
                        state: state,
                        availability: .unavailable(.init(code: .evaluationFailed, message: String(describing: error)))
                    )
                }
            }
            """),
            DeclSyntax(stringLiteral: """
            public func machineObservation() async -> TLAMachineObservation {
                synchronousMachineObservation()
            }
            """),
        ]
    }
}
