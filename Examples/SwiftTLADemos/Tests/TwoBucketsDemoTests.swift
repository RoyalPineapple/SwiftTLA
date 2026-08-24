import Testing
@testable import SwiftTLADemos

struct TwoBucketsDemoTests {
    @Test("two buckets exposes all generated puzzle moves")
    func exposesPuzzleMoves() throws {
        var machine = TwoBuckets()

        #expect(try machine.isEnabled(.fillThree))
        #expect(try machine.isEnabled(.fillFive))
        #expect(try machine.isEnabled(.emptyThree) == false)

        _ = try machine.send(.fillThree)
        #expect(machine.state.three == 3)
        #expect(machine.state.five == 0)

        _ = try machine.send(.pourThreeIntoFive)
        #expect(machine.state.three == 0)
        #expect(machine.state.five == 3)
    }

}
