import SwiftTLA
import SwiftTLAMacros

/// Dijkstra's original mutual-exclusion algorithm, bounded to the four
/// processes in the published LSpec model.
///
/// `temporary` begins as the upstream model's opaque `defaultInitValue`.
/// It then holds either the current owner or the set of peers still to
/// inspect. `OneOf` keeps that source-level TLA+ union explicit in Swift
/// without changing its formal representation.
@TLAModel
public struct DijkstraMutexModel: Sendable {
    public enum Process: String, CaseIterable, FiniteDomainKey {
        case one = "p1"
        case two = "p2"
        case three = "p3"

        public static let formalDomain = allCases
        public static let formalTypeIdentity = FormalTypeIdentity(rawValue: "upstream.dijkstra-mutex.process")

        public var tlaValue: TLAValue { .string(rawValue) }
    }

    private enum Label: String, PlusCalLabel {
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
    private enum TemporaryInitial: String, TLAValueType {
        case notAssigned = "defaultInitValue"
    }

    private typealias ActiveTemporary = OneOf<Process, SetExpr<Process>>
    private typealias Temporary = OneOf<TemporaryInitial, ActiveTemporary>

    public static var spec: TLASpec {
        #spec("DijkstraMutex") {
            Extends("Integers")
            Algorithm("Mutex") {
                let b = SharedVar(initial: Function<Process, Bool>.literal(
                    (.one, true), (.two, true), (.three, true)
                ))
                let c = SharedVar(initial: Function<Process, Bool>.literal(
                    (.one, true), (.two, true), (.three, true)
                ))
                let k = SharedVar(in: SetExpr<Process>.literal(.one, .two, .three))

                Each(Process.all, fairness: .weak) { selfID in
                    let temporary = LocalVar(
                        initial: OneOf<TemporaryInitial, OneOf<Process, SetExpr<Process>>>.first(.notAssigned)
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
                            to: OneOf<TemporaryInitial, OneOf<Process, SetExpr<Process>>>.second(
                                OneOf<Process, SetExpr<Process>>.first(k.expr)
                            )
                        )
                    }

                    Do(Label.li3b) {
                        let active = temporary.expr.assumingSecond(ActiveTemporary.self)
                        let owner = active.assumingFirst(Process.self)
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
                            to: OneOf<TemporaryInitial, OneOf<Process, SetExpr<Process>>>.second(OneOf<Process, SetExpr<Process>>.second(
                                SetExpr<Process>.literal(.one, .two, .three).removing(selfID)
                            )
                        )
                        )
                    }

                    Do(Label.li4b) {
                        let active = temporary.expr.assumingSecond(ActiveTemporary.self)
                        let remaining = active.assumingSecond(SetExpr<Process>.self)
                        If(!remaining.isEmpty) {
                            With(remaining) { process in
                                Assign(
                                    temporary,
                                    to: OneOf<TemporaryInitial, OneOf<Process, SetExpr<Process>>>.second(OneOf<Process, SetExpr<Process>>.second(
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
                }

                Invariant("MutualExclusion") {
                    All(Process.all) { first in
                        All(Process.all) { second in
                            first == second || !(At(Label.critical, first) && At(Label.critical, second))
                        }
                    }
                }
            }
        }
    }
}

extension Example {
    public static let dijkstraMutex = Entry(
        id: "dijkstra-mutex/LSpec_N3",
        upstreamSpec: "dijkstra-mutex",
        upstreamModule: "specifications/dijkstra-mutex/DijkstraMutex.toolbox/LSpec-model/MC.tla",
        upstreamCfg: "specifications/dijkstra-mutex/DijkstraMutex.toolbox/LSpec-model/MC.cfg",
        expectedDistinct: 90_882,
        verificationStateLimit: 100_000,
        spec: DijkstraMutexModel.spec,
        notes: "Published three-process Dijkstra mutex. TLC = 90,882."
    )
}
