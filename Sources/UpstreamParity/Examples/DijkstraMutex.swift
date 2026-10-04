import SwiftTLA
import SwiftTLAMacros

/// This partial Dijkstra model has the upstream three- and four-process populations.
/// It does not yet match either published TLC configuration.
///
/// `temporary` begins as the upstream model's opaque `defaultInitValue`.
/// It then holds either the current owner or the set of peers still to
/// inspect. `OneOf` keeps that source-level TLA+ union explicit in Swift and
/// preserves its formal representation.
@TLAModel
package struct DijkstraMutexModel: Sendable {
    package enum Process: String, CaseIterable, FiniteTLAValueDomain {
        case one = "p1"
        case two = "p2"
        case three = "p3"
        case four = "p4"

        package static var defaultValue: Self { .one }
        package static let finiteValues = allCases

        package var tlaValue: TLAValue { .constant(rawValue) }
    }

    private enum Label: String, CaseIterable {
        case li0 = "Li0"
        case li1 = "Li1"
        case li2 = "Li2"
        case li3a = "Li3a"
        case li3b = "Li3b"
        case li3c = "Li3c"
        case li3d = "Li3d"
        case li4a = "Li4a"
        case li4b = "Li4b"
        case critical = "cs"
        case li5 = "Li5"
        case li6 = "Li6"
        case nonCritical = "ncs"
    }

    /// The published model's value before a process first writes `temp`.
    /// It is distinct from every process and set value.
    enum TemporaryInitial: String, TLAValueType {
        case notAssigned = "defaultInitValue"

        static var defaultValue: Self { .notAssigned }
        var tlaValue: TLAValue { .constant(rawValue) }
    }

    private typealias ActiveTemporary = OneOf<Process, Set<Process>>

    package static var spec: TLASpec {
        #spec("DijkstraMutex") { (scope: SpecificationScope) in
            Extends(.integers)
            let Proc = scope.parameter(as: Set<Process>.self, in: Set<Set<Process>>([
                Set<Process>([.one, .two, .three]),
                Set<Process>([.one, .two, .three, .four]),
            ]))
            let MutualExclusion = Invariant()
            let Mutex = Algorithm(scoped: { scope in
                let b = scope.sharedVar(initial: Dictionary<Process, Bool>.mapping(over: Proc) { _ in true })
                let c = scope.sharedVar(initial: Dictionary<Process, Bool>.mapping(over: Proc) { _ in true })
                let k = scope.sharedVar(in: Proc)

                Each(Proc, fairness: .weak, scoped: { selfID, scope in
                    let temporary = scope.localVar(initial: OneOf<TemporaryInitial, OneOf<Process, Set<Process>>>.first(.notAssigned)
                    )

                    Do(Label.li0) {
                        Assign(b, to: b.updating(selfID, to: false))
                    }

                    Do(Label.li1) {
                        If(k != selfID) {
                            Goto(Label.li2)
                        } else: {
                            Goto(Label.li4a)
                        }
                    }

                    Do(Label.li2) {
                        Assign(c, to: c.updating(selfID, to: true))
                    }

                    Do(Label.li3a) {
                        Assign(
                            temporary,
                            to: OneOf<TemporaryInitial, OneOf<Process, Set<Process>>>.second(
                                OneOf<Process, Set<Process>>.first(k.expr)
                            )
                        )
                    }

                    Do(Label.li3b) {
                        let active = temporary.expr.assuming(ActiveTemporary.self)
                        let owner = active.assuming(Process.self)
                        If(b[owner]) {
                            Goto(Label.li3c)
                        } else: {
                            Goto(Label.li3d)
                        }
                    }

                    Do(Label.li3c) {
                        Assign(k, to: selfID.expr)
                    }

                    Do(Label.li3d) {
                        Goto(Label.li1)
                    }

                    Do(Label.li4a) {
                        Assign(c, to: c.updating(selfID, to: false))
                        Assign(
                            temporary,
                            to: OneOf<TemporaryInitial, OneOf<Process, Set<Process>>>.second(OneOf<Process, Set<Process>>.second(
                                Proc.removing(selfID)
                            )
                        )
                        )
                    }

                    Do(Label.li4b) {
                        let active = temporary.expr.assuming(ActiveTemporary.self)
                        let remaining = active.assuming(Set<Process>.self)
                        If(!remaining.isEmpty) {
                            With(remaining) { process in
                                Assign(
                                    temporary,
                                    to: OneOf<TemporaryInitial, OneOf<Process, Set<Process>>>.second(OneOf<Process, Set<Process>>.second(
                                        remaining.removing(process)
                                    )
                                )
                                )
                                If(!c[process]) {
                                    Goto(Label.li1)
                                } else: {
                                    Goto(Label.li4b)
                                }
                            }
                        } else: {
                            Goto(Label.critical)
                        }
                    }

                    Do(Label.critical) { Skip() }
                    Do(Label.li5) { Assign(c, to: c.updating(selfID, to: true)) }
                    Do(Label.li6) { Assign(b, to: b.updating(selfID, to: true)) }
                    Do(Label.nonCritical) { Goto(Label.li0) }
                })

                MutualExclusion {
                    ForAll(in: Proc) { first in
                        ForAll(in: Proc) { second in
                            first == second || !(At(Label.critical, first) && At(Label.critical, second))
                        }
                    }
                }
            })
            Mutex
            let Safety4Processors = Validation {
                Bind(Proc, to: Set<Process>([.one, .two, .three, .four]))
            }
            Safety4Processors
        }
    }
}

extension Example {
    package static let dijkstraMutex = FiniteModelFixture(
        expectedDistinct: 90_882,
        maximumStateLimit: 100_000,
        spec: DijkstraMutexModel.spec,
    )
}
