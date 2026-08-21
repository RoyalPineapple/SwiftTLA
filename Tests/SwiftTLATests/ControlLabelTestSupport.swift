@testable import SwiftTLA

enum TestControlLabel: String, PlusCalLabel, CaseIterable {
    case acquire
    case advance
    case changed
    case check
    case choose
    case copy
    case done
    case enter
    case finish
    case finished
    case hold
    case increment
    case keep
    case mark
    case open
    case otherProcess
    case prepare
    case release
    case `repeat`
    case start
    case stay
    case stop
    case stringProcess
    case sum
    case swap
    case tick
    case vote
    case write
    case writeFirst
}
