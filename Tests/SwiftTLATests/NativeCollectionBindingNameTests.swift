import Testing
@testable import SwiftTLA
import SwiftTLAMacros

// Formal boundary fixture intentionally uses generated implementation names.
@TLAModel
private struct CollectionBindingNames {
    struct Device: Identifiable, Sendable { let id: Int }
    static var spec: TLASpec {
        #spec("CollectionBindingNames") {
            let state = SymmetricCollectionVar<Device, Int>("state")
            SymmetricCollection(state, verificationScope: 1, initial: 0)
            CollectionAction("updateState", on: state) { member in
                state[member] == 0 && state.update(member, to: 1)
            }
            let execution = SymmetricCollectionVar<Device, Int>("execution")
            SymmetricCollection(execution, verificationScope: 1, initial: 0)
            CollectionAction("updateExecution", on: execution) { member in
                execution[member] == 0 && execution.update(member, to: 1)
            }
            let enabled = SymmetricCollectionVar<Device, Int>("enabled")
            SymmetricCollection(enabled, verificationScope: 1, initial: 0)
            CollectionAction("updateEnabled", on: enabled) { member in
                enabled[member] == 0 && enabled.update(member, to: 1)
            }
            let result = SymmetricCollectionVar<Device, Int>("result")
            SymmetricCollection(result, verificationScope: 1, initial: 0)
            CollectionAction("updateResult", on: result) { member in
                result[member] == 0 && result.update(member, to: 1)
            }
            let action = SymmetricCollectionVar<Device, Int>("action")
            SymmetricCollection(action, verificationScope: 1, initial: 0)
            CollectionAction("updateAction", on: action) { member in
                action[member] == 0 && action.update(member, to: 1)
            }
            let next = SymmetricCollectionVar<Device, Int>("next")
            SymmetricCollection(next, verificationScope: 1, initial: 0)
            CollectionAction("updateNext", on: next) { member in
                next[member] == 0 && next.update(member, to: 1)
            }
            let machine = SymmetricCollectionVar<Device, Int>("machine")
            SymmetricCollection(machine, verificationScope: 1, initial: 0)
            CollectionAction("updateMachine", on: machine) { member in
                machine[member] == 0 && machine.update(member, to: 1)
            }
        }
    }
}

@Suite("Collection bindings preserve public names without generated collisions")
struct NativeCollectionBindingNameTests {
    @Test("Collection IDs stay separate from execution locals and public state")
    func collectionNamesDoNotCaptureGeneratedLocals() throws {
        var machine = try CollectionBindingNames.makeMachine(state: [1], execution: [2], enabled: [3], result: [4], action: [5], next: [6], machine: [7])
        #expect(try machine.enabledActions().count == 7)
        _ = try machine.send(.updateState(member: 1))
        #expect(machine.state.state == [1: 1])
        _ = try machine.send(.updateExecution(member: 2))
        #expect(machine.state.execution == [2: 1])
        _ = try machine.send(.updateEnabled(member: 3))
        #expect(machine.state.enabled == [3: 1])
        _ = try machine.send(.updateResult(member: 4))
        #expect(machine.state.result == [4: 1])
        _ = try machine.send(.updateAction(member: 5))
        #expect(machine.state.action == [5: 1])
        _ = try machine.send(.updateNext(member: 6))
        #expect(machine.state.next == [6: 1])
        _ = try machine.send(.updateMachine(member: 7))
        #expect(machine.state.machine == [7: 1])
        #expect(try machine.enabledActions().isEmpty)
    }

    @Test("Actor construction retains collection bindings named machine and state")
    func actorCollectionNamesDoNotCaptureStorage() async throws {
        let actor = try CollectionBindingNames.Actor(state: [1], execution: [2], enabled: [3], result: [4], action: [5], next: [6], machine: [7])
        _ = try await actor.send(.updateMachine(member: 7))
        #expect((await actor.state).machine == [7: 1])
        #expect((await actor.state).state == [1: 0])
    }
}
