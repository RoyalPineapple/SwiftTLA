@testable import SwiftTLAPlugin
import Foundation
import Testing
@testable import SwiftTLA
import SwiftTLAMacros
import SwiftParser
import SwiftSyntax

struct GeneratedSequentialMachineTests {
    @Test("a sequential Algorithm advances its typed state")
    func generatedSequentialAlgorithmAdvancesTypedState() throws {

        var machine = try GeneratedSequentialCounter.makeMachine()
        let transition = try machine.send(.increment)
        #expect(transition.after.count == 1)
    }
}
