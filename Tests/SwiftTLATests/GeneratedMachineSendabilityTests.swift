import Testing
import SwiftTLA
import SwiftTLAMacros

// Public, non-frozen structs do not gain implicit Sendable conformance.
@TLAModel
public struct TransferableCounter {
    enum Step: String, CaseIterable { case advance }
    static var spec: TLASpec {
        #spec("TransferableCounter") {
            let transferableCounter = Algorithm(label: "TransferableCounter", scoped: { scope in
                let count = scope.sharedVar(_name: "count", initial: 0)
                Do(Step.advance) { Assign(count, to: count + 1) }
            })
            transferableCounter
        }
    }
}

@TLAModel
public struct ExplicitlyTransferableCounter: Sendable {
    enum Step: String, CaseIterable { case advance }
    static var spec: TLASpec {
        #spec("ExplicitlyTransferableCounter") {
            let explicitlyTransferableCounter = Algorithm(label: "ExplicitlyTransferableCounter", scoped: { scope in
                let count = scope.sharedVar(_name: "count", initial: 0)
                Do(Step.advance) { Assign(count, to: count + 1) }
            })
            explicitlyTransferableCounter
        }
    }
}

@Suite struct GeneratedMachineSendabilityTests {
    @Test("generated machine and scenario values have compiler-checked Sendable conformance")
    func generatedValueConformance() throws {
        func requireSendable<Value: Sendable>(_: Value.Type) {}
        requireSendable(TransferableCounter.self)
        requireSendable(TransferableCounter.State.self)
        requireSendable(TransferableCounter.Action.self)
        requireSendable(TransferableCounter.Transition.self)
        requireSendable(TransferableCounter.Snapshot.self)
        requireSendable(TransferableCounter.CheckingRegisters.self)
        requireSendable(TransferableCounter.Property.self)
        requireSendable(TransferableCounter.Actor.self)
        requireSendable(ExplicitlyTransferableCounter.self)
        requireSendable(ScenarioExpectations.Configuration.self)
        requireSendable(ScenarioExpectations.ValidationScenario.self)
        var machine = try TransferableCounter.makeMachine()
        #expect(try machine.send(.advance).after.count == 1)
    }
}
