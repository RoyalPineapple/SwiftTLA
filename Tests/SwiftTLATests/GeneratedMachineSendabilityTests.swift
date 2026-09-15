import Testing
import SwiftTLA
import SwiftTLAMacros

// Public, non-frozen structs do not gain implicit Sendable conformance.
@TLAModel
public struct TransferableCounter {
    enum Step: String, CaseIterable { case advance }
    static var spec: TLASpec {
        #spec("TransferableCounter") {
            Algorithm("TransferableCounter", scoped: { scope in
                let count = scope.sharedVar("count", initial: 0)
                Do(Step.advance) { Assign(count, to: count + 1) }
            })
        }
    }
}

@TLAModel
public struct ExplicitlyTransferableCounter: Sendable {
    enum Step: String, CaseIterable { case advance }
    static var spec: TLASpec {
        #spec("ExplicitlyTransferableCounter") {
            Algorithm("ExplicitlyTransferableCounter", scoped: { scope in
                let count = scope.sharedVar("count", initial: 0)
                Do(Step.advance) { Assign(count, to: count + 1) }
            })
        }
    }
}

@Suite struct GeneratedMachineSendabilityTests {
    @Test("public generated machines satisfy Sendable with generated or explicit conformance")
    func publicMachineConformance() throws {
        func requireSendable<Value: Sendable>(_: Value.Type) {}
        requireSendable(TransferableCounter.self)
        requireSendable(TransferableCounter.State.self)
        requireSendable(TransferableCounter.Action.self)
        requireSendable(TransferableCounter.Transition.self)
        requireSendable(ExplicitlyTransferableCounter.self)
        var machine = try TransferableCounter.makeMachine()
        #expect(try machine.send(.advance).after.count == 1)
    }
}
