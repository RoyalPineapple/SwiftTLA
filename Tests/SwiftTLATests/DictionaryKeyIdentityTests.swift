import Testing
import SwiftTLA

struct DictionaryKeyIdentityTests {
    @Test func generatedStateAndTransitionsPreserveEnumKeysAndValues() throws {
        var machine = try DictionaryKeyIdentityModel.makeMachine()
        #expect(machine.state.values == [.first: 1, .second: 2])
        #expect(machine.state.links == [.first: .second, .second: .first])
        #expect(machine.state.labels == [.first: .first, .second: .second])

        let transition = try machine.send(.update)
        #expect(transition.before.values[.first] == 1)
        #expect(transition.after.values == [.first: 2, .second: 2])
        #expect(transition.after.labels == [.first: .second, .second: .second])
        #expect(transition.after.links == transition.before.links)
        #expect(machine.state == transition.after)
    }

    @Test func generatedEnumProjectionRejectsOtherRepresentations() {
        typealias Key = DictionaryKeyIdentityModel.Key
        typealias Label = DictionaryKeyIdentityModel.Label
        #expect(Key.finiteValues == [.first, .second])
        #expect(Key(formalValue: .int(1)) == .first)
        #expect(Key(formalValue: .int(3)) == nil)
        #expect(Key(formalValue: .string("first")) == nil)
        #expect(Label(formalValue: .string("first")) == .first)
        #expect(Label(formalValue: .string("unknown")) == nil)
        #expect(Label(formalValue: .int(1)) == nil)
    }
}
