import SwiftTLA

extension Example {
    public static let barrierN6 = Entry(
        id: "barriers/Barrier_N6",
        upstreamSpec: "barriers",
        upstreamModule: "specifications/barriers/Barrier.tla",
        upstreamCfg: "specifications/barriers/Barrier.cfg",
        expectedDistinct: 64,
        spec: barrierSpec(n: 6),
        notes: "N=6. TLC = 64.",
    )

static func barrierSpec(n: Int) -> TLASpec {
        // Explicit N=6 (upstream Barrier.cfg)
        precondition(n == 6)
        let p1 = Var<String>("pc1")
        let p2 = Var<String>("pc2")
        let p3 = Var<String>("pc3")
        let p4 = Var<String>("pc4")
        let p5 = Var<String>("pc5")
        let p6 = Var<String>("pc6")
        return TLASpec("Barrier") {
            Extends("Integers")
            Variable(p1, "b0"); Variable(p2, "b0"); Variable(p3, "b0")
            Variable(p4, "b0"); Variable(p5, "b0"); Variable(p6, "b0")
            Action("b0_1") { p1 == "b0" && p1.becomes("b1") }
            Action("b0_2") { p2 == "b0" && p2.becomes("b1") }
            Action("b0_3") { p3 == "b0" && p3.becomes("b1") }
            Action("b0_4") { p4 == "b0" && p4.becomes("b1") }
            Action("b0_5") { p5 == "b0" && p5.becomes("b1") }
            Action("b0_6") { p6 == "b0" && p6.becomes("b1") }
            Action("b1_release") {
                p1 == "b1" && p2 == "b1" && p3 == "b1" && p4 == "b1" && p5 == "b1" && p6 == "b1"
                    && p1.becomes("b0") && p2.becomes("b0") && p3.becomes("b0")
                    && p4.becomes("b0") && p5.becomes("b0") && p6.becomes("b0")
            }
        }
    }

}
