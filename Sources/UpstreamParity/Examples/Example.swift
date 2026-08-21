import SwiftTLA

public enum Example {
    public struct Entry: Sendable {
        public let id: String
        public let upstreamSpec: String
        public let upstreamModule: String
        public let upstreamCfg: String?
        public let expectedDistinct: Int
        public let maximumStateLimit: Int
        public let spec: TLASpec
        public let notes: String

        public init(id: String, upstreamSpec: String, upstreamModule: String, upstreamCfg: String?,
                    expectedDistinct: Int, maximumStateLimit: Int = 50_000,
                    spec: TLASpec, notes: String) {
            self.id = id; self.upstreamSpec = upstreamSpec; self.upstreamModule = upstreamModule
            self.upstreamCfg = upstreamCfg; self.expectedDistinct = expectedDistinct
            self.maximumStateLimit = maximumStateLimit
            self.spec = spec; self.notes = notes
        }
    }
    public static let all: [Entry] = [
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
