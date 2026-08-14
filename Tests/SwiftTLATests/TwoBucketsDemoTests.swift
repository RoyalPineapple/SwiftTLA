import Testing
@testable import SwiftTLADemos

struct TwoBucketsDemoTests {
    @Test("two buckets exposes all generated puzzle moves")
    func exposesPuzzleMoves() throws {
        var machine = TwoBuckets()

        #expect(try machine.availableActions() == [
            .fillThree,
            .fillFive
        ])

        _ = try machine.apply(.fillThree)
        #expect(machine.state.three == 3)
        #expect(machine.state.five == 0)

        _ = try machine.apply(.pourThreeIntoFive)
        #expect(machine.state.three == 0)
        #expect(machine.state.five == 3)
    }
}
