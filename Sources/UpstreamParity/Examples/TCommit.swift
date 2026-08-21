import SwiftTLA
import SwiftTLAMacros

/// Lamport's transaction-commit protocol over three resource managers.
///
/// The resource-manager state is one finite, typed formal function. The three
/// parameterized actions retain the upstream transition relation without
/// manufacturing a separate action for each manager in Swift.
@TLAModel
public struct TCommitModel: Sendable {
    public enum ResourceManager: String, CaseIterable, FiniteDomainKey {
        case one = "r1"
        case two = "r2"
        case three = "r3"

        public static var defaultValue: Self { .one }
        public static let formalDomain = allCases
        public static let formalTypeIdentity = FormalTypeIdentity(rawValue: "examples.tcommit.resourceManager")

        public var tlaValue: TLAValue { .string(rawValue) }
    }

    public enum ManagerState: String, TLAValueType {
        case working
        case prepared
        case committed
        case aborted

        public static var defaultValue: Self { .working }
    }

    private enum Step: String, PlusCalLabel, CaseIterable {
        case operate
    }

    public static var spec: TLASpec {
        #spec("TCommit") {
            Extends(.integers)
            let rmState = SharedVar("rmState", initial: Function<ResourceManager, ManagerState>.literal(
                (.one, .working), (.two, .working), (.three, .working)
            ))

            Algorithm("TCommit") {
                Each(ResourceManager.all) { rm in
                    Do(Step.operate) {
                        Either {
                            When(rmState[rm] == .working)
                            Assign(rmState, to: rmState.updating(rm, to: .prepared))
                        } or: {
                            Either {
                                When(rmState[rm] == .prepared)
                                When(rmState[.one] == .prepared || rmState[.one] == .committed)
                                When(rmState[.two] == .prepared || rmState[.two] == .committed)
                                When(rmState[.three] == .prepared || rmState[.three] == .committed)
                                Assign(rmState, to: rmState.updating(rm, to: .committed))
                            } or: {
                                When(rmState[rm] == .working || rmState[rm] == .prepared)
                                When(rmState[.one] != .committed)
                                When(rmState[.two] != .committed)
                                When(rmState[.three] != .committed)
                                Assign(rmState, to: rmState.updating(rm, to: .aborted))
                            }
                        }
                        Goto(Step.operate)
                    }
                }
            }

            Invariant("TCConsistent") {
                !(rmState[.one] == .aborted && rmState[.two] == .committed)
                    && !(rmState[.one] == .aborted && rmState[.three] == .committed)
                    && !(rmState[.two] == .aborted && rmState[.one] == .committed)
                    && !(rmState[.two] == .aborted && rmState[.three] == .committed)
                    && !(rmState[.three] == .aborted && rmState[.one] == .committed)
                    && !(rmState[.three] == .aborted && rmState[.two] == .committed)
            }
        }
    }
}

extension Example {
    public static let tCommit = Entry(
        id: "transaction_commit/TCommit",
        upstreamSpec: "transaction_commit",
        upstreamModule: "specifications/transaction_commit/TCommit.tla",
        upstreamCfg: "specifications/transaction_commit/TCommit.cfg",
        expectedDistinct: 34,
        spec: TCommitModel.spec,
        notes: "Lamport TCommit. Typed resource-manager function and parameterized actions. TLC = 34."
    )
}
