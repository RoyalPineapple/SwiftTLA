import SwiftTLA
import SwiftTLAMacros

/// Two bounded instances of the upstream `Simple` PlusCal algorithm.
///
/// The upstream model has one `x` and one `y` function, indexed by the
/// process identifier. `Each` lowers to exactly that function-shaped state
/// and its generated `pc` function; the Swift source does not unroll a
/// separate action or program counter for every process.
@TLAModel
public struct TeachingSimpleN2Model {
    public enum Process: Int, CaseIterable, FiniteDomainKey {
        case p0
        case p1

        public static let formalDomain = allCases
        public static let formalTypeIdentity = FormalTypeIdentity(
            rawValue: "upstream.teaching-concurrency.simple.n2.process"
        )
        public var tlaValue: TLAValue { .int(rawValue) }
    }

    private enum Step: String, PlusCalLabel {
        case a
        case b
    }

    public static var spec: TLASpec {
        #spec("Simple") {
            Extends("Integers")
            Algorithm("Simple") {
                let x = SharedVar(initial: Function<Process, Int>.literal(
                    (.p0, 0), (.p1, 0)
                ))
                let y = SharedVar(initial: Function<Process, Int>.literal(
                    (.p0, 0), (.p1, 0)
                ))

                Each(Process.all) { process in
                    Do(Step.a) {
                        Assign(x, to: x.updating(process, to: 1))
                    }
                    Do(Step.b) {
                        If(process == .p0) {
                            Assign(y, to: y.updating(process, to: x[.p1]))
                        } else: {
                            Assign(y, to: y.updating(process, to: x[.p0]))
                        }
                    }
                }

                // Keep one formal predicate per line. The builder combines
                // these clauses with conjunction, exactly as upstream TypeOK.
                Invariant("TypeOK") {
                    x[.p0] == 0 || x[.p0] == 1
                    x[.p1] == 0 || x[.p1] == 1
                    y[.p0] == 0 || y[.p0] == 1
                    y[.p1] == 0 || y[.p1] == 1
                }
            }
        }
    }
}

@TLAModel
public struct TeachingSimpleN3Model {
    public enum Process: Int, CaseIterable, FiniteDomainKey {
        case p0
        case p1
        case p2

        public static let formalDomain = allCases
        public static let formalTypeIdentity = FormalTypeIdentity(
            rawValue: "upstream.teaching-concurrency.simple.n3.process"
        )
        public var tlaValue: TLAValue { .int(rawValue) }
    }

    private enum Step: String, PlusCalLabel {
        case a
        case b
    }

    public static var spec: TLASpec {
        #spec("Simple") {
            Extends("Integers")
            Algorithm("Simple") {
                let x = SharedVar(initial: Function<Process, Int>.literal(
                    (.p0, 0), (.p1, 0), (.p2, 0)
                ))
                let y = SharedVar(initial: Function<Process, Int>.literal(
                    (.p0, 0), (.p1, 0), (.p2, 0)
                ))

                Each(Process.all) { process in
                    Do(Step.a) {
                        Assign(x, to: x.updating(process, to: 1))
                    }
                    Do(Step.b) {
                        If(process == .p0) {
                            Assign(y, to: y.updating(process, to: x[.p2]))
                        } else: {
                            If(process == .p1) {
                                Assign(y, to: y.updating(process, to: x[.p0]))
                            } else: {
                                Assign(y, to: y.updating(process, to: x[.p1]))
                            }
                        }
                    }
                }

                // See the N=2 instance for why this is one predicate per
                // builder line rather than a host-language boolean loop.
                Invariant("TypeOK") {
                    x[.p0] == 0 || x[.p0] == 1
                    x[.p1] == 0 || x[.p1] == 1
                    x[.p2] == 0 || x[.p2] == 1
                    y[.p0] == 0 || y[.p0] == 1
                    y[.p1] == 0 || y[.p1] == 1
                    y[.p2] == 0 || y[.p2] == 1
                }
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
        notes: "N=2, one PlusCal process family with function-shaped x, y, and pc state. TLC = 13."
    )

    public static let teachingSimpleN3 = Entry(
        id: "TeachingConcurrency/Simple_N3",
        upstreamSpec: "TeachingConcurrency",
        upstreamModule: "specifications/TeachingConcurrency/Simple.tla",
        upstreamCfg: nil,
        expectedDistinct: 51,
        spec: TeachingSimpleN3Model.spec,
        notes: "N=3, one PlusCal process family with function-shaped x, y, and pc state. TLC = 51."
    )
}
