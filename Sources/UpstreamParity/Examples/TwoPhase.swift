import SwiftTLA
import SwiftTLAMacros

/// Lamport's two-phase commit protocol with three resource managers.
///
/// The coordinator and each resource manager are independently scheduled
/// PlusCal-shaped processes. Messages are a typed formal record set, not a
/// Swift dictionary or a raw string-keyed state value.
public struct TwoPhaseModel: Sendable {
    public enum ResourceManager: String, CaseIterable, FiniteDomainKey {
        case one = "r1"
        case two = "r2"
        case three = "r3"

        public static var defaultValue: Self { .one }
        public static let formalDomain = allCases
        public static let formalTypeIdentity = FormalTypeIdentity(rawValue: "examples.twoPhase.resourceManager")

        public var tlaValue: TLAValue { .string(rawValue) }
    }

    public enum Coordinator: String, CaseIterable, FiniteDomainKey {
        case transactionManager

        public static var defaultValue: Self { .transactionManager }
        public static let formalDomain = allCases
        public static let formalTypeIdentity = FormalTypeIdentity(rawValue: "examples.twoPhase.coordinator")

        public var tlaValue: TLAValue { .string(rawValue) }
    }

    public enum ResourceManagerState: String, TLAValueType {
        case working
        case prepared
        case committed
        case aborted

        public static var defaultValue: Self { .working }
    }

    public enum TransactionManagerState: String, TLAValueType {
        case initial = "init"
        case committed
        case aborted

        public static var defaultValue: Self { .initial }
    }

    public enum MessageKind: String, TLAValueType {
        case prepared
        case commit
        case abort

        public static var defaultValue: Self { .prepared }
    }

    public struct MessageFields {
        public let kind: MessageKind
        public let resourceManager: ResourceManager
    }

    public enum MessageSchema: TLARecordSchema {
        public typealias Fields = MessageFields

        public static let fieldNames: Set<String> = ["kind", "rm"]
        public static let defaultRecord: TLAValue = .record([
            "kind": .string(MessageKind.prepared.rawValue),
            "rm": .string(ResourceManager.one.rawValue)
        ])

        public static func fieldName<Value>(for field: KeyPath<MessageFields, Value>) -> String? {
            let key = field as AnyKeyPath
            if key == \MessageFields.kind { return "kind" }
            if key == \MessageFields.resourceManager { return "rm" }
            return nil
        }

        public static let kind = field(\MessageFields.kind)
        public static let resourceManager = field(\MessageFields.resourceManager)
    }

    private enum ResourceManagerStep: String, PlusCalLabel, CaseIterable {
        case resourceManagerOperate
    }

    private enum CoordinatorStep: String, PlusCalLabel, CaseIterable {
        case coordinatorOperate
    }

    public static var spec: TLASpec {
        #spec("TwoPhase") {
            Extends(.integers)
            Algorithm("TwoPhase", scoped: { scope in
                let resourceManagerState = scope.sharedVar("resourceManagerState", initial: Function<ResourceManager, ResourceManagerState>.literal(
                    (ResourceManager.one, ResourceManagerState.working),
                    (ResourceManager.two, ResourceManagerState.working),
                    (ResourceManager.three, ResourceManagerState.working)
                ))
                let transactionManagerState = scope.sharedVar("transactionManagerState", initial: TransactionManagerState.initial)
                let prepared = scope.sharedVar("prepared", initial: SetExpr<ResourceManager>())
                let messages = scope.sharedVar("messages", initial: SetExpr<Record<MessageSchema>>())

                Each(ResourceManager.all) { resourceManager in
                    Do(ResourceManagerStep.resourceManagerOperate) {
                        Either {
                            When(resourceManagerState[resourceManager] == ResourceManagerState.working)
                            Assign(resourceManagerState, to: resourceManagerState.updating(resourceManager, to: ResourceManagerState.prepared))
                            Assign(messages, to: messages.inserting(Record<MessageSchema>.literal(
                                .init(MessageSchema.kind, MessageKind.prepared),
                                .init(MessageSchema.resourceManager, resourceManager)
                            )))
                        } or: {
                            Either {
                                When(resourceManagerState[resourceManager] == ResourceManagerState.working)
                                Assign(resourceManagerState, to: resourceManagerState.updating(resourceManager, to: ResourceManagerState.aborted))
                            } or: {
                                Either {
                                    When(messages.contains(Record<MessageSchema>.literal(
                                        .init(MessageSchema.kind, MessageKind.commit),
                                        .init(MessageSchema.resourceManager, ResourceManager.one)
                                    )))
                                    Assign(resourceManagerState, to: resourceManagerState.updating(resourceManager, to: ResourceManagerState.committed))
                                } or: {
                                    When(messages.contains(Record<MessageSchema>.literal(
                                        .init(MessageSchema.kind, MessageKind.abort),
                                        .init(MessageSchema.resourceManager, ResourceManager.one)
                                    )))
                                    Assign(resourceManagerState, to: resourceManagerState.updating(resourceManager, to: ResourceManagerState.aborted))
                                }
                            }
                        }
                        Goto(ResourceManagerStep.resourceManagerOperate)
                    }
                }

                Each(Coordinator.all) { _ in
                    Do(CoordinatorStep.coordinatorOperate) {
                        Either {
                            With(ResourceManager.all) { resourceManager in
                                When(transactionManagerState == TransactionManagerState.initial)
                                When(messages.contains(Record<MessageSchema>.literal(
                                    .init(MessageSchema.kind, MessageKind.prepared),
                                    .init(MessageSchema.resourceManager, resourceManager)
                                )))
                                Assign(prepared, to: prepared.inserting(resourceManager))
                            }
                        } or: {
                            Either {
                                When(transactionManagerState == TransactionManagerState.initial)
                                When(prepared.cardinality == 3)
                                Assign(transactionManagerState, to: TransactionManagerState.committed)
                                Assign(messages, to: messages.inserting(Record<MessageSchema>.literal(
                                    .init(MessageSchema.kind, MessageKind.commit),
                                    .init(MessageSchema.resourceManager, ResourceManager.one)
                                )))
                            } or: {
                                When(transactionManagerState == TransactionManagerState.initial)
                                Assign(transactionManagerState, to: TransactionManagerState.aborted)
                                Assign(messages, to: messages.inserting(Record<MessageSchema>.literal(
                                    .init(MessageSchema.kind, MessageKind.abort),
                                    .init(MessageSchema.resourceManager, ResourceManager.one)
                                )))
                            }
                        }
                        Goto(CoordinatorStep.coordinatorOperate)
                    }
                }
            })

        }
    }
}

extension Example {
    public static let twoPhase = Entry(
        id: "transaction_commit/TwoPhase",
        upstreamSpec: "transaction_commit",
        upstreamModule: "specifications/transaction_commit/TwoPhase.tla",
        upstreamCfg: "specifications/transaction_commit/TwoPhase.cfg",
        expectedDistinct: 288,
        spec: TwoPhaseModel.spec,
        notes: "Lamport TwoPhase safety. Typed resource-manager and message records. TLC = 288."
    )
}
