import SwiftTLA
import SwiftTLAMacros

/// The published eight-process bounded model of PlusCal `SimpleRegular`.
///
/// Unlike `Simple`, each shared register holds the set of values a concurrent
/// read may observe. The three labels are the upstream regular-register
/// write/write/read steps; this is not a sequential Swift simulation.
@TLAModel
public struct TeachingSimpleRegularN8Model: Sendable {
    public enum Process: Int, CaseIterable, FiniteDomainKey {
        case p0, p1, p2, p3, p4, p5, p6, p7

        public static var defaultValue: Self { .p0 }
        public static let formalDomain = allCases
        public static let formalTypeIdentity = FormalTypeIdentity(
            rawValue: "upstream.teaching-concurrency.simple-regular.n8.process"
        )
        public var tlaValue: TLAValue { .int(rawValue) }
    }

    private enum Step: String, PlusCalLabel, CaseIterable {
        case a1
        case a2
        case b
    }

    public static var spec: TLASpec {
        #spec("SimpleRegular") {
            Extends(.integers)
            Algorithm("SimpleRegular") {
                let x = SharedVar("x", initial: Function<Process, SetExpr<Int>>.literal(
                    (.p0, SetExpr<Int>.literal(0)), (.p1, SetExpr<Int>.literal(0)),
                    (.p2, SetExpr<Int>.literal(0)), (.p3, SetExpr<Int>.literal(0)),
                    (.p4, SetExpr<Int>.literal(0)), (.p5, SetExpr<Int>.literal(0)),
                    (.p6, SetExpr<Int>.literal(0)), (.p7, SetExpr<Int>.literal(0))
                ))
                let y = SharedVar("y", initial: Function<Process, Int>.literal(
                    (.p0, 0), (.p1, 0), (.p2, 0), (.p3, 0),
                    (.p4, 0), (.p5, 0), (.p6, 0), (.p7, 0)
                ))
                let predecessor = Function<Process, Process>.literal(
                    (.p0, .p7), (.p1, .p0), (.p2, .p1), (.p3, .p2),
                    (.p4, .p3), (.p5, .p4), (.p6, .p5), (.p7, .p6)
                )

                Each(Process.all) { process in
                    Do(Step.a1) {
                        Assign(x, to: x.updating(process, to: SetExpr<Int>.literal(0, 1)))
                    }
                    Do(Step.a2) {
                        Assign(x, to: x.updating(process, to: SetExpr<Int>.literal(1)))
                    }
                    Do(Step.b) {
                        With(x[predecessor[process]]) { value in
                            Assign(y, to: y.updating(process, to: value.expr))
                        }
                    }
                }

                Invariant("PCorrect") {
                    !All(Process.all) { process in Finished(process) }
                        || !All(Process.all) { process in y[process] != 1 }
                }
                Invariant("TypeOK") {
                    All(Process.all) { process in y[process] == 0 || y[process] == 1 }
                }
            }
        }
    }
}

extension Example {
    public static let teachingSimpleRegularN8 = Entry(
        id: "TeachingConcurrency/SimpleRegular_N8",
        upstreamSpec: "TeachingConcurrency",
        upstreamModule: "specifications/TeachingConcurrency/SimpleRegular.tla",
        upstreamCfg: "specifications/TeachingConcurrency/SimpleRegular.cfg",
        expectedDistinct: 277_726,
        maximumStateLimit: 300_000,
        spec: TeachingSimpleRegularN8Model.spec,
        notes: "N=8 regular-register process family. TLC = 277,726."
    )
}
