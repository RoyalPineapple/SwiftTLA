import SwiftTLA
import SwiftTLAMacros

@TLAModel
public struct BarrierModel {
    public enum BarrierPhase: String, TLAValueType {
        case b0, b1
    }

    public static var spec: TLASpec {
        #spec("Barrier") {
            Extends("Integers")
            let pc1 = SharedVar(initial: BarrierPhase.b0)
            let pc2 = SharedVar(initial: BarrierPhase.b0)
            let pc3 = SharedVar(initial: BarrierPhase.b0)
            let pc4 = SharedVar(initial: BarrierPhase.b0)
            let pc5 = SharedVar(initial: BarrierPhase.b0)
            let pc6 = SharedVar(initial: BarrierPhase.b0)
            Action("b0_1") { pc1 == BarrierPhase.b0 && pc1.becomes(BarrierPhase.b1) }
            Action("b0_2") { pc2 == BarrierPhase.b0 && pc2.becomes(BarrierPhase.b1) }
            Action("b0_3") { pc3 == BarrierPhase.b0 && pc3.becomes(BarrierPhase.b1) }
            Action("b0_4") { pc4 == BarrierPhase.b0 && pc4.becomes(BarrierPhase.b1) }
            Action("b0_5") { pc5 == BarrierPhase.b0 && pc5.becomes(BarrierPhase.b1) }
            Action("b0_6") { pc6 == BarrierPhase.b0 && pc6.becomes(BarrierPhase.b1) }
            Action("b1_release") {
                pc1 == BarrierPhase.b1 && pc2 == BarrierPhase.b1 && pc3 == BarrierPhase.b1 && pc4 == BarrierPhase.b1 && pc5 == BarrierPhase.b1 && pc6 == BarrierPhase.b1
                    && pc1.becomes(BarrierPhase.b0) && pc2.becomes(BarrierPhase.b0) && pc3.becomes(BarrierPhase.b0)
                    && pc4.becomes(BarrierPhase.b0) && pc5.becomes(BarrierPhase.b0) && pc6.becomes(BarrierPhase.b0)
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
