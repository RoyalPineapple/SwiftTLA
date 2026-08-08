import SwiftTLA

extension Example {
    public static let teachingSimpleN2 = Entry(
        id: "TeachingConcurrency/Simple_N2",
        upstreamSpec: "TeachingConcurrency",
        upstreamModule: "specifications/TeachingConcurrency/Simple.tla",
        upstreamCfg: nil,
        expectedDistinct: 13,
        spec: teachingSimple(n: 2),
        notes: "PlusCal translation, N=2. Upstream TLC (TypeOK only) = 13.",
    )

    public static let teachingSimpleN3 = Entry(
        id: "TeachingConcurrency/Simple_N3",
        upstreamSpec: "TeachingConcurrency",
        upstreamModule: "specifications/TeachingConcurrency/Simple.tla",
        upstreamCfg: nil,
        expectedDistinct: 13,
        spec: teachingSimple(n: 3),
        notes: "N=3. Upstream TLC = 51. (cfg default N=5 → 723).",
    )

    /// Flattened TeachingConcurrency Simple for small N (2 or 3).
static func teachingSimple(n: Int) -> TLASpec {
        precondition(n == 2 || n == 3)
        if n == 2 {
            let x0 = Var<Int>("x0", value: 0), x1 = Var<Int>("x1", value: 0)
            let y0 = Var<Int>("y0", value: 0), y1 = Var<Int>("y1", value: 0)
            let pc0 = Var<String>("pc0", value: "a"), pc1 = Var<String>("pc1", value: "a")
            return TLASpec("Simple") {
                Extends("Integers")
                Variable(x0, 0); Variable(x1, 0)
                Variable(y0, 0); Variable(y1, 0)
                Variable(pc0, "a"); Variable(pc1, "a")
                Action("a0") { pc0 == "a" && x0.becomes(1) && pc0.becomes("b") }
                Action("b0") { pc0 == "b" && y0.becomes(x1) && pc0.becomes("Done") }
                Action("a1") { pc1 == "a" && x1.becomes(1) && pc1.becomes("b") }
                Action("b1") { pc1 == "b" && y1.becomes(x0) && pc1.becomes("Done") }
                Action("Terminating") { pc0 == "Done" && pc1 == "Done" }
                Invariant("TypeOK") {
                    (x0 == 0 || x0 == 1) && (x1 == 0 || x1 == 1)
                        && (y0 == 0 || y0 == 1) && (y1 == 0 || y1 == 1)
                }
            }
        }
        let x0 = Var<Int>("x0", value: 0), x1 = Var<Int>("x1", value: 0), x2 = Var<Int>("x2", value: 0)
        let y0 = Var<Int>("y0", value: 0), y1 = Var<Int>("y1", value: 0), y2 = Var<Int>("y2", value: 0)
        let pc0 = Var<String>("pc0", value: "a"), pc1 = Var<String>("pc1", value: "a"), pc2 = Var<String>("pc2", value: "a")
        return TLASpec("Simple") {
            Extends("Integers")
            Variable(x0, 0); Variable(x1, 0); Variable(x2, 0)
            Variable(y0, 0); Variable(y1, 0); Variable(y2, 0)
            Variable(pc0, "a"); Variable(pc1, "a"); Variable(pc2, "a")
            Action("a0") { pc0 == "a" && x0.becomes(1) && pc0.becomes("b") }
            Action("b0") { pc0 == "b" && y0.becomes(x2) && pc0.becomes("Done") }
            Action("a1") { pc1 == "a" && x1.becomes(1) && pc1.becomes("b") }
            Action("b1") { pc1 == "b" && y1.becomes(x0) && pc1.becomes("Done") }
            Action("a2") { pc2 == "a" && x2.becomes(1) && pc2.becomes("b") }
            Action("b2") { pc2 == "b" && y2.becomes(x1) && pc2.becomes("Done") }
            Action("Terminating") { pc0 == "Done" && pc1 == "Done" && pc2 == "Done" }
            Invariant("TypeOK") {
                (x0 == 0 || x0 == 1) && (x1 == 0 || x1 == 1) && (x2 == 0 || x2 == 1)
            }
        }
    }

}
