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

    @Test("SingleLaneBridge compiles one typed direct model with its published action labels")
    func compilesTypedDirectModel() throws {
        let compilation = try SingleLaneBridgeModel.spec.compile()

        #expect(compilation.spec.actions.map(\.name) == [
            "MoveOutside_r1", "MoveInside_r1", "Enter_r1",
            "MoveOutside_r2", "MoveInside_r2", "Enter_r2",
            "MoveOutside_l1", "MoveInside_l1", "Enter_l1",
            "MoveOutside_l2", "MoveInside_l2", "Enter_l2",
        ])
        #expect(compilation.spec.formalOperatorDefinitions.map(\.name) == [
            "IsRight", "InBridge", "NextLocation", "LocationAt", "CarsOnBridge",
        ])
        #expect(compilation.description.variables.map(\.name) == [
            "Location", "WaitingBeforeBridge",
        ])
    }
}
