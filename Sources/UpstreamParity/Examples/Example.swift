import SwiftTLA

public enum Example {
    public struct Entry: Sendable {
        public let id: String
        public let upstreamSpec: String
        public let upstreamModule: String
        public let upstreamCfg: String?
        public let spec: TLASpec
        public let notes: String

        public init(id: String, upstreamSpec: String, upstreamModule: String, upstreamCfg: String?,
                    spec: TLASpec, notes: String) {
            self.id = id; self.upstreamSpec = upstreamSpec; self.upstreamModule = upstreamModule
            self.upstreamCfg = upstreamCfg; self.spec = spec; self.notes = notes
        }
    }
    public static let all: [Entry] = [
        asynchInterface,
        bakeryN2,
        barrierN6,
        catEvenBoxes,
        catOddBoxes,
        chameneosM4N4,
        changRobertsN3,
        channel,
        cigaretteSmokers,
        coffeeCanMax100,
        coffeeCanMax5,
        dieHardTypeOK,
        diningPhilosophersNP5,
        ewd840,
        ewd998,
        hourClock,
        hourClock2,
        lamportMutexN2,
        paxosSmall,
        prisonerN3,
        prisoners4,
        simpleAllocator,
        singleLaneBridge,
        syncTD,
        tCommit,
        teachingSimpleN2,
        teachingSimpleN3,
        twoPhase
    ]
}
