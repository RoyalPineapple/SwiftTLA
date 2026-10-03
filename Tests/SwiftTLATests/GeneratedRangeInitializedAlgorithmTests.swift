import Testing

struct GeneratedRangeInitializedAlgorithmTests {
    @Test("generated initialization preserves every finite shared value")
    func generatedRangePreservesEveryInitialHour() throws {
        let machines = try GeneratedRangeInitializedAlgorithm.initialMachines()
        #expect(machines.count == 3)
        #expect(Set(machines.map { $0.state.hour }) == [1, 2, 3])
    }
}
