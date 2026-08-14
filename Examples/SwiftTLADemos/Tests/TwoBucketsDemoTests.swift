import Testing
@testable import SwiftTLADemos

struct TwoBucketsDemoTests {
    @Test("two buckets exposes all generated puzzle moves")
    func exposesPuzzleMoves() throws {
        var machine = TwoBuckets()

        try TwoBuckets.verifySpec()

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

    @Test("two buckets provides a generated observable adapter")
    @MainActor
    func providesObservableAdapter() async throws {
        let machine = TwoBuckets.Observable()
        _ = try await machine.execute(TwoBuckets.Observable.ActionLabel.fillFive.toInvocation())

        #expect(machine.state.five == 5)
    }
}
