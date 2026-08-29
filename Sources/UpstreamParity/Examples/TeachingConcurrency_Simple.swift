import SwiftTLA
import SwiftTLAMacros

/// Two bounded instances of the upstream `Simple` PlusCal algorithm.
///
/// The upstream model has one `x` and one `y` function, indexed by the
/// process identifier. `Each` lowers to that function-shaped state and its
/// generated `pc` function.
package struct TeachingSimpleN2Model: Sendable {
    package enum Process: Int, CaseIterable, FiniteTLAValueDomain {
        case p0
        case p1

        package static var defaultValue: Self { .p0 }
        package static let finiteValues = allCases
        package var tlaValue: TLAValue { .int(rawValue) }
    }

    private enum Step: String, CaseIterable {
        case a
        case b
    }

    package static var spec: TLASpec {
        #spec("Simple") {
            Extends(.integers)
            Algorithm("Simple", scoped: { scope in
                let x = scope.sharedVar("x", initial: Function<Process, Int>.literal(
                    (.p0, 0), (.p1, 0)
                ))
                let y = scope.sharedVar("y", initial: Function<Process, Int>.literal(
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
            })
        }
    }
}

package struct TeachingSimpleN3Model: Sendable {
    package enum Process: Int, CaseIterable, FiniteTLAValueDomain {
        case p0
        case p1
        case p2

        package static var defaultValue: Self { .p0 }
        package static let finiteValues = allCases
        package var tlaValue: TLAValue { .int(rawValue) }
    }

    private enum Step: String, CaseIterable {
        case a
        case b
    }

    package static var spec: TLASpec {
        #spec("Simple") {
            Extends(.integers)
            Algorithm("Simple", scoped: { scope in
                let x = scope.sharedVar("x", initial: Function<Process, Int>.literal(
                    (.p0, 0), (.p1, 0), (.p2, 0)
                ))
                let y = scope.sharedVar("y", initial: Function<Process, Int>.literal(
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
            })
        }
    }
}

extension Example {
    package static let teachingSimpleN2 = FiniteModelFixture(
        expectedDistinct: 13,
        maximumStateLimit: 50_000,
        spec: TeachingSimpleN2Model.spec,
    )

    package static let teachingSimpleN3 = FiniteModelFixture(
        expectedDistinct: 51,
        maximumStateLimit: 50_000,
        spec: TeachingSimpleN3Model.spec,
    )
}
