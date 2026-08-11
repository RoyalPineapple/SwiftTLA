import SwiftTLA
import SwiftTLAMacros

@TLAModel
public struct BarrierModel {
    public static var spec: TLASpec {
        return TLASpec("Barrier") {
            Extends("Integers")
            let pc1 = Var<String>("pc1")
            let pc2 = Var<String>("pc2")
            let pc3 = Var<String>("pc3")
            let pc4 = Var<String>("pc4")
            let pc5 = Var<String>("pc5")
            let pc6 = Var<String>("pc6")
            Variable(pc1, "b0"); Variable(pc2, "b0"); Variable(pc3, "b0")
            Variable(pc4, "b0"); Variable(pc5, "b0"); Variable(pc6, "b0")
            Action("b0_1") { pc1 == "b0" && pc1.becomes("b1") }
            Action("b0_2") { pc2 == "b0" && pc2.becomes("b1") }
            Action("b0_3") { pc3 == "b0" && pc3.becomes("b1") }
            Action("b0_4") { pc4 == "b0" && pc4.becomes("b1") }
            Action("b0_5") { pc5 == "b0" && pc5.becomes("b1") }
            Action("b0_6") { pc6 == "b0" && pc6.becomes("b1") }
            Action("b1_release") {
                pc1 == "b1" && pc2 == "b1" && pc3 == "b1" && pc4 == "b1" && pc5 == "b1" && pc6 == "b1"
                    && pc1.becomes("b0") && pc2.becomes("b0") && pc3.becomes("b0")
                    && pc4.becomes("b0") && pc5.becomes("b0") && pc6.becomes("b0")
            }
        }
    }
}

extension Example {
    public static let barrierN6 = Entry(
        id: "barriers/Barrier_N6",
        upstreamSpec: "barriers",
        upstreamModule: "specifications/barriers/Barrier.tla",
        upstreamCfg: "specifications/barriers/Barrier.cfg",
        expectedDistinct: 64,
        spec: BarrierModel.spec,
        notes: "N=6. TLC = 64.",
    )
}
