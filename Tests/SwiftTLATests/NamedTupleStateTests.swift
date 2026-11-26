import SwiftTLA
import Testing

struct NamedTupleStateTests {
    @Test("The generated machine retains named Swift values and their declared slot order")
    func retainsSlotOrder() throws {
        var machine = try NamedTupleStateModel.makeMachine()
        let before: NamedTupleStateModel.Coordinates = machine.state.point
        let empty: NamedTupleStateModel.Empty = machine.state.empty
        let single: NamedTupleStateModel.Single = machine.state.single
        #expect(empty.tlaValue == .tuple([]))
        #expect(single.tlaValue == .tuple([.int(7)]))
        #expect(before.tlaValue == .tuple([1, 2, 3, 4, 5, 6].map(TLAValue.int)))
        let tracePoint = TLAValue.tuple([1, 2, 3, 4, 5, 6].map(TLAValue.int))
        let decoded = try #require(NamedTupleStateModel.Coordinates(formalValue: tracePoint))
        machine = try NamedTupleStateModel.makeMachine(.init(point: decoded, empty: empty, single: single))
        _ = try machine.send(.rotate)
        #expect(machine.state.point.tlaValue == .tuple([6, 1, 2, 3, 4, 7].map(TLAValue.int)))
    }

    @Test("Decoding a named tuple requires every slot to have its declared type")
    func validatesFormalValues() {
        typealias Single = NamedTupleStateModel.Single
        #expect(Single(formalValue: .tuple([.int(4)]))?.sample == 4)
        #expect(Single(formalValue: .tuple([])) == nil)
        #expect(Single(formalValue: .tuple([.int(4), .int(0)])) == nil)
        #expect(Single(formalValue: .tuple([.string("4")])) == nil)
        #expect(Single(formalValue: .record(["sample": .int(4)])) == nil)
    }
}
