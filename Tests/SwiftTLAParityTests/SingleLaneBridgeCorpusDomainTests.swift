import Testing
import SwiftTLA
@testable import UpstreamParity

struct SingleLaneBridgeCorpusDomainTests {
    @Test("SingleLaneBridge keeps its upstream finite constant domains")
    func preservesFiniteConstantDomains() {
        #expect(SingleLaneBridgeModel.spec.constants == [
            ConstantDecl("CarsRight", .set([.string("r1"), .string("r2")])),
            ConstantDecl("CarsLeft", .set([.string("l1"), .string("l2")])),
            ConstantDecl("Bridge", .set([.int(4), .int(5)])),
            ConstantDecl("Positions", .set([.int(1), .int(2), .int(3), .int(4), .int(5), .int(6), .int(7), .int(8)])),
        ])
    }
}
