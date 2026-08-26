import SwiftTLA

package enum Example {
    package struct Entry: Sendable {
        package let id: String
        package let upstreamSpec: String
        package let upstreamModule: String
        package let upstreamCfg: String?
        package let expectedDistinct: Int
        package let maximumStateLimit: Int
        package let spec: TLASpec
        package let notes: String

        package init(id: String, upstreamSpec: String, upstreamModule: String, upstreamCfg: String?,
                    expectedDistinct: Int, maximumStateLimit: Int = 50_000,
                    spec: TLASpec, notes: String) {
            self.id = id; self.upstreamSpec = upstreamSpec; self.upstreamModule = upstreamModule
            self.upstreamCfg = upstreamCfg; self.expectedDistinct = expectedDistinct
            self.maximumStateLimit = maximumStateLimit
            self.spec = spec; self.notes = notes
        }
    }
    package static let all: [Entry] = [
        asynchInterface,
        gameOfLife,
        nanoBlockchain,
        bakeryN2,
        boulanger,
        binarySearch,
        barrierN6,
        barriersN6,
        catEvenBoxes,
        catOddBoxes,
        chameneosM4N4,
        changRobertsN3,
        channel,
        cigaretteSmokers,
        coffeeCanMax100,
        coffeeCanMax5,
        consensus,
        voteProof,
        dieHardTypeOK,
        diningPhilosophersNP5,
        dijkstraMutex,
        ewd840,
        ewd998,
        echo,
        findHighest,
        hourClock,
        hourClock2,
        lamportMutexN2,
        leastCircularSubstring,
        lockTwoProcess,
        multiCarElevator,
        nQueensFour,
        parallelReachable,
        paxosSmall,
        petersonTwoProcess,
        prisonerN3,
        prisoners4,
        simpleAllocator,
        singleLaneBridge,
        syncTD,
        sumSequence,
        reachable,
        tCommit,
        teachingSimpleN2,
        teachingSimpleN3,
        teachingSimpleRegularN8,
        twoPhase,
        twoPhaseWithBackupManager
    ]
}
