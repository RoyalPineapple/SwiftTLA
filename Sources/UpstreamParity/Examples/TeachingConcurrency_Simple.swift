import SwiftTLA
import SwiftTLAMacros

/// The program-counter labels in the small Teaching Concurrency PlusCal model.
public enum TeachingSimplePhase: String, TLAValueType {
    case a
    case b
    case done = "Done"
}

@TLAModel
public struct TeachingSimpleN2Model {
    public static var spec: TLASpec {
        #spec("Simple") {
            Extends("Integers")
            let x0 = SharedVar(initial: 0)
            let x1 = SharedVar(initial: 0)
            let y0 = SharedVar(initial: 0)
            let y1 = SharedVar(initial: 0)
            let pc0 = SharedVar(initial: TeachingSimplePhase.a)
            let pc1 = SharedVar(initial: TeachingSimplePhase.a)

            Action("a0") { pc0 == TeachingSimplePhase.a && x0.becomes(1) && pc0.becomes(.b) }
            Action("b0") { pc0 == TeachingSimplePhase.b && y0.becomes(x1) && pc0.becomes(.done) }
            Action("a1") { pc1 == TeachingSimplePhase.a && x1.becomes(1) && pc1.becomes(.b) }
            Action("b1") { pc1 == TeachingSimplePhase.b && y1.becomes(x0) && pc1.becomes(.done) }
            Action("Terminating") { pc0 == TeachingSimplePhase.done && pc1 == TeachingSimplePhase.done }

            Invariant("TypeOK") {
                (x0 == 0 || x0 == 1) && (x1 == 0 || x1 == 1)
                    && (y0 == 0 || y0 == 1) && (y1 == 0 || y1 == 1)
            }
        }
    }
}

@TLAModel
public struct TeachingSimpleN3Model {
    public static var spec: TLASpec {
        #spec("Simple") {
            Extends("Integers")
            let x0 = SharedVar(initial: 0)
            let x1 = SharedVar(initial: 0)
            let x2 = SharedVar(initial: 0)
            let y0 = SharedVar(initial: 0)
            let y1 = SharedVar(initial: 0)
            let y2 = SharedVar(initial: 0)
            let pc0 = SharedVar(initial: TeachingSimplePhase.a)
            let pc1 = SharedVar(initial: TeachingSimplePhase.a)
            let pc2 = SharedVar(initial: TeachingSimplePhase.a)

            Action("a0") { pc0 == TeachingSimplePhase.a && x0.becomes(1) && pc0.becomes(.b) }
            Action("b0") { pc0 == TeachingSimplePhase.b && y0.becomes(x2) && pc0.becomes(.done) }
            Action("a1") { pc1 == TeachingSimplePhase.a && x1.becomes(1) && pc1.becomes(.b) }
            Action("b1") { pc1 == TeachingSimplePhase.b && y1.becomes(x0) && pc1.becomes(.done) }
            Action("a2") { pc2 == TeachingSimplePhase.a && x2.becomes(1) && pc2.becomes(.b) }
            Action("b2") { pc2 == TeachingSimplePhase.b && y2.becomes(x1) && pc2.becomes(.done) }
            Action("Terminating") {
                pc0 == TeachingSimplePhase.done
                    && pc1 == TeachingSimplePhase.done
                    && pc2 == TeachingSimplePhase.done
            }

            Invariant("TypeOK") {
                (x0 == 0 || x0 == 1) && (x1 == 0 || x1 == 1) && (x2 == 0 || x2 == 1)
            }
        }
    }
}

extension Example {
    public static let teachingSimpleN2 = Entry(
        id: "TeachingConcurrency/Simple_N2",
        upstreamSpec: "TeachingConcurrency",
        upstreamModule: "specifications/TeachingConcurrency/Simple.tla",
        upstreamCfg: nil,
        expectedDistinct: 13,
        spec: TeachingSimpleN2Model.spec,
        notes: "PlusCal translation, N=2. Typed program-counter phases. Upstream TLC (TypeOK only) = 13."
    )

    public static let teachingSimpleN3 = Entry(
        id: "TeachingConcurrency/Simple_N3",
        upstreamSpec: "TeachingConcurrency",
        upstreamModule: "specifications/TeachingConcurrency/Simple.tla",
        upstreamCfg: nil,
        expectedDistinct: 51,
        spec: TeachingSimpleN3Model.spec,
        notes: "PlusCal translation, N=3. Typed program-counter phases. Upstream TLC = 51."
    )
}
