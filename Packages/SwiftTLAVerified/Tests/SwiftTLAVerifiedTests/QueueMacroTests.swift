@testable import SwiftTLAVerified
import XCTest

final class QueueMacroTests: XCTestCase {
    func testGenericModelVerificationUsesExplicitInstanceFactory() throws {
        try Queue<Int>.verifyTransitions(makeInstance: { Queue<Int>(capacity: 4) })
        try Queue<Int>.verifyInvariants(makeInstance: { Queue<Int>(capacity: 4) })
    }
}
