import SwiftSyntax
import SwiftTLA

extension MacroExpander {
    static func generateCanonicalMachineMembers(
        isActor: Bool,
        hasActions: Bool,
        symmetricCollections: [SpecParser.ParsedSymmetricCollection] = []
    ) -> [DeclSyntax] {
        let modifier = isActor ? "" : "mutating "
        let labelField = hasActions ? "public let label: ActionLabel" : ""
        let labelValidation = hasActions ? """
                guard let label = ActionLabel(invocation: invocation) else {
                    throw GeneratedMachineError.unrepresentableActionLabel(invocation)
                }
        """ : ""
        let labelArgument = hasActions ? "label: label," : ""
        let typedApply = hasActions ? """
            public \(modifier)func apply(_ label: ActionLabel) throws -> TransitionEvidence {
                try apply(label.toInvocation())
            }
            """ : ""
        let availableActions = hasActions ? """
            public func availableActions() throws -> [ActionLabel] {
                try _machine.availableInvocations(in: _stateWithLiveCollections()).map { invocation in
                    guard let label = ActionLabel(invocation: invocation) else {
                        throw GeneratedMachineError.unrepresentableActionLabel(invocation)
                    }
                    return label
                }
            }
            """ : """
            public func availableInvocations() throws -> [TLAActionInvocation] {
                try _machine.availableInvocations(in: _stateWithLiveCollections())
            }
            """
        let liveProjection = symmetricCollections.map {
            "state = try state.replacing(\($0.name).projection().modelValue, for: .init(validating: Variables.\($0.name).rawValue)!)"
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
            public struct TransitionEvidence: Sendable, Equatable {
                \(labelField)
                public let invocation: TLAActionInvocation
                public let before: [String: TLAValue]
                public let after: [String: TLAValue]
            }
            """),
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
            public \(modifier)func apply(_ invocation: TLAActionInvocation) throws -> TransitionEvidence {
                \(labelValidation)
                let evidence = try _machine.apply(invocation, from: _stateWithLiveCollections()) { _ in true }
                return TransitionEvidence(
                    \(labelArgument)
                    invocation: invocation,
                    before: evidence.before.asDictionary,
                    after: evidence.after.asDictionary
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
                    return .init(state: state, availability: .available(try _machine.availableInvocations(in: projection)))
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
            DeclSyntax(stringLiteral: """
            public \(modifier)func executeSynchronously(_ invocation: TLAActionInvocation) throws -> TransitionEvidence {
                try apply(invocation)
            }
            """),
            DeclSyntax(stringLiteral: """
            public \(modifier)func execute(_ invocation: TLAActionInvocation) async throws -> TransitionEvidence {
                try apply(invocation)
            }
            """)
        ]
    }
}
