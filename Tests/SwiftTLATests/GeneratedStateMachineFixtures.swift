@testable import SwiftTLAPlugin
import Foundation
import Testing
@testable import SwiftTLA
import SwiftTLAMacros
import SwiftParser
import SwiftSyntax

@TLAModel
struct SanitizedActionModel {
    static var spec: TLASpec {
        #spec("SanitizedActionModel") {
            let value = Var<Int>("value")
            Variable(value, 0)
            SwiftTLA.Action("procedure.work.enter") { value.becomes(1) }
            SwiftTLA.Action("procedure_work_enter") { value.becomes(2) }
            SwiftTLA.Action("step-2") { value.becomes(3) }
        }
    }
}

@TLAModel
struct InvocationNamedActionModel {
    static var spec: TLASpec {
        #spec("InvocationNamedActionModel") {
            let value = Var<Int>("value")
            Variable(value, 0)
            SwiftTLA.Action("toInvocation") { value.becomes(1) }
        }
    }
}

@TLAModel
struct CounterNoInvs {
    static var spec: TLASpec {
        TLASpec("CounterNoInvs") {
            let x = Var<Int>("x")
            Variable(x, 0)
            SwiftTLA.Action("inc") { x.becomes(x + 1).when(x < 3) }
            SwiftTLA.Action("dec") { x.becomes(x - 1).when(x > 0) }
        }
    }
}

@TLAModel
struct GeneratedAlgorithmCounter {
    enum Step: String, CaseIterable { case increment }

    enum Node: String, CaseIterable, FiniteTLAValueDomain {
        case left
        case right

        static var defaultValue: Self { .left }
        static let finiteValues = allCases
        var tlaValue: TLAValue { .string(rawValue) }
    }

    static var spec: TLASpec {
        #spec("GeneratedAlgorithmCounter") {
            Algorithm("GeneratedAlgorithmCounter", scoped: { scope in
                let count = scope.sharedVar("count", initial: 0)
                Each(Node.all, fairness: .weak) { _ in
                    While(Step.increment, count < 2) {
                        When(count < 2)
                        Assert(count >= 0)
                        Assign(count, to: count + 1)
                    }
                }
            })
        }
    }
}

@TLAModel
struct SeededCounterMachine {
    enum Step: String, CaseIterable { case advance }

    static var spec: TLASpec {
        #spec("SeededCounterMachine") {
            Algorithm("SeededCounterMachine", scoped: { scope in
                let value = scope.sharedVar("value", in: 0...2)

                While(Step.advance, true) {
                    Either {
                        When(value < 2)
                        Assign(value, to: value + 1)
                    } or: {
                        When(value == 2)
                        Assign(value, to: 0)
                    }
                }
            })
        }
    }
}

@TLAModel
struct GeneratedRestrictedProcessDomain {
    enum Step: String, CaseIterable { case increment }

    enum Member: Int, CaseIterable, FiniteTLAValueDomain {
        case worker = 1

        static var defaultValue: Self { .worker }
        static let finiteValues = allCases
        var tlaValue: TLAValue { .int(rawValue) }
    }

    static var spec: TLASpec {
        #spec("GeneratedRestrictedProcessDomain") {
            Algorithm("GeneratedRestrictedProcessDomain", scoped: { scope in
                let count = scope.sharedVar("count", initial: 0)
                Each(Member.all) { _ in
                    Do(Step.increment) {
                        Assign(count, to: count + 1)
                    }
                }
            })
        }
    }
}

@TLAModel
struct GeneratedSequentialCounter {
    enum Step: String, CaseIterable {
        case increment
        case finish
    }

    static var spec: TLASpec {
        #spec("GeneratedSequentialCounter") {
            Algorithm("GeneratedSequentialCounter", scoped: { scope in
                let count = scope.sharedVar("count", initial: 0)
                Do(Step.increment) {
                    Let(count + 1) { nextCount in
                        Assign(count, to: nextCount.expr)
                    }
                }
                Do(Step.finish) {
                    Stop()
                }
            })
        }
    }
}

@TLAModel
struct GeneratedSimultaneousSwap {
    enum Step: String, CaseIterable { case swap }

    static var spec: TLASpec {
        #spec("GeneratedSimultaneousSwap") {
            Algorithm("GeneratedSimultaneousSwap", scoped: { scope in
                let left = scope.sharedVar("left", initial: 1)
                let right = scope.sharedVar("right", initial: 2)
                Do(Step.swap) {
                    Assign(left, to: right)
                    Assign(right, to: left)
                }
            })
        }
    }
}

@TLAModel
struct GeneratedPairPattern {
    enum Step: String, CaseIterable { case choose }

    static var spec: TLASpec {
        #spec("GeneratedPairPattern") {
            Algorithm("GeneratedPairPattern", scoped: { scope in
                let selected = scope.sharedVar("selected", initial: 0)
                Do(Step.choose) {
                    With(SetExpr<Pair<Int, Bool>>.literal(
                        Pair(first: 1, second: true),
                        Pair(first: 2, second: false)
                    )) { number, flag in
                        Assert((number.expr == 1) || !flag.expr)
                        Assign(selected, to: number.expr)
                    }
                }
            })
        }
    }
}

@TLAModel
struct GeneratedDuplicateSuccessor {
    enum Step: String, CaseIterable { case choose }

    static var spec: TLASpec {
        #spec("GeneratedDuplicateSuccessor") {
            Algorithm("GeneratedDuplicateSuccessor", scoped: { scope in
                let selected = scope.sharedVar("selected", initial: 0)
                Do(Step.choose) {
                    With(SetExpr<Int>.literal(1, 2)) { _ in
                        Assign(selected, to: 1)
                    }
                }
            })
        }
    }
}

@TLAModel
struct GeneratedRangeInitializedAlgorithm {
    enum Step: String, CaseIterable { case advance }

    enum Node: String, CaseIterable, FiniteTLAValueDomain {
        case clock

        static var defaultValue: Self { .clock }
        static let finiteValues = allCases
        var tlaValue: TLAValue { .string(rawValue) }
    }

    static var spec: TLASpec {
        #spec("GeneratedRangeInitializedAlgorithm") {
            Algorithm("GeneratedRangeInitializedAlgorithm", scoped: { scope in
                let hour = scope.sharedVar("hour", in: 1...3)
                Each(Node.all) { _ in
                    Do(Step.advance) {
                        When(hour < 3)
                        Assign(hour, to: hour + 1)
                    }
                }
            })
        }
    }
}

@TLAModel
struct GeneratedIntegerChoiceAlgorithm {
    enum Step: String, CaseIterable { case choose }

    enum Node: String, CaseIterable, FiniteTLAValueDomain {
        case only

        static var defaultValue: Self { .only }
        static let finiteValues = allCases
        var tlaValue: TLAValue { .string(rawValue) }
    }

    static var spec: TLASpec {
        #spec("GeneratedIntegerChoice") {
            Algorithm("GeneratedIntegerChoice", scoped: { scope in
                let selected = scope.sharedVar("selected", initial: 0)
                Each(Node.all) { _ in
                    Do(Step.choose) {
                        Choose(1...3) { choice in
                            Assign(selected, to: choice.expr)
                        }
                    }
                }
            })
        }
    }
}

@TLAModel
struct GeneratedAlgorithmStateConstraint {
    enum Step: String, CaseIterable { case advance }

    static var spec: TLASpec {
        #spec("GeneratedAlgorithmStateConstraint") {
            Algorithm("GeneratedAlgorithmStateConstraint", scoped: { scope in
                let count = scope.sharedVar("count", initial: 0)
                Do(Step.advance) {
                    Assign(count, to: count + 1)
                }
                StateConstraint(count < 2)
            })
        }
    }
}

@TLAModel
struct GeneratedProcessLocalInvariant {
    enum Node: String, CaseIterable, FiniteTLAValueDomain {
        case left
        case right

        static var defaultValue: Self { .left }
        static let finiteValues = allCases
        var tlaValue: TLAValue { .string(rawValue) }
    }

    enum Label: String, CaseIterable {
        case receive
    }

    static var spec: TLASpec {
        #spec("GeneratedProcessLocalInvariant") {
            Algorithm("GeneratedProcessLocalInvariant", scoped: { scope in
                Each(Node.all, scoped: { selfID, scope in
                    let count = scope.localVar("count", initial: 0)
                    Do(Label.receive) {
                        Skip()
                    }
                    Invariant("LocalCount") { count == 0 }
                    Invariant("ControlLocation") {
                        At(Label.receive, selfID) || Finished(selfID)
                    }
                })
            })
        }
    }
}

@TLAModel
struct GeneratedDependentInitialAlgorithm {
    enum Step: String, CaseIterable { case stop }

    enum Node: String, CaseIterable, FiniteTLAValueDomain {
        case left
        case right

        static var defaultValue: Self { .left }
        static let finiteValues = allCases
        var tlaValue: TLAValue { .string(rawValue) }
    }

    enum Phase: String, CaseIterable, FiniteTLAValueDomain {
        case active
        case inactive

        static var defaultValue: Self { .active }
        static let finiteValues = allCases
        var tlaValue: TLAValue { .string(rawValue) }
    }

    static var spec: TLASpec {
        #spec("GeneratedDependentInitialAlgorithm") {
            Algorithm("GeneratedDependentInitialAlgorithm", scoped: { scope in
                let seed = scope.sharedVar("seed", in: SetExpr<Bool>.literal(false, true))
                let mirrors = scope.sharedVar("mirrors", initial: Function<Node, Phase>.mapping { node in
                    If(node == Node.left && seed == true, then: Phase.active, else: Phase.inactive)
                })
                Each(Node.all) { _ in
                    Do(Step.stop) {
                        Assign(mirrors, to: mirrors)
                        Stop()
                    }
                }
            })
        }
    }
}

@TLAModel
struct CounterWithInv {
    static var spec: TLASpec {
        TLASpec("CounterWithInv") {
            let x = Var<Int>("x")
            Variable(x, 0)
            SwiftTLA.Action("inc") { x.becomes(x + 1).when(x < 5) }
            Invariant("nonNeg") { x >= 0 }
        }
    }
}

@TLAModel
struct MultiVar {
    static var spec: TLASpec {
        TLASpec("MultiVar") {
            let a = Var<Int>("a")
            let b = Var<Int>("b")
            Variable(a, 0)
            Variable(b, 0)
            SwiftTLA.Action("incA") { a.becomes(a + 1).when(a < 2) }
            SwiftTLA.Action("incB") { b.becomes(b + 1).when(b < 2) }
            Invariant("sumLE4") { (a + b) <= 4 }
        }
    }
}

@TLAModel
struct GeneratedAlgorithmMachine {
    enum Step: String, CaseIterable { case tick }

    static var spec: TLASpec {
        #spec("GeneratedAlgorithmMachine") {
            Algorithm("GeneratedAlgorithmMachine", scoped: { scope in
                let count = scope.sharedVar("count", initial: 1)
                Do(Step.tick) {
                    If(count < 12) {
                        Assign(count, to: count + 1)
                    } else: {
                        Assign(count, to: 1)
                    }
                }
                Invariant("valid") { count >= 1 && count <= 12 }
            })
        }
    }
}

@TLAModel
struct SingleParameterActionMachine {
    static var spec: TLASpec {
        TLASpec("SingleParameterActionMachine") {
            let value = Var<Int>("value")
            Variable(value, 0)
            SwiftTLA.Action("select", parameters: [ActionParameter("choice", values: [1, 2])]) {
                value.becomes(1)
            }
        }
    }

}

@TLAModel
struct ThreeParameterActionMachine {
    static var spec: TLASpec {
        TLASpec("ThreeParameterActionMachine") {
            let value = Var<Int>("value")
            Variable(value, 0)
            SwiftTLA.Action("transfer", parameters: [
                ActionParameter("source", values: [1, 2]),
                ActionParameter("destination", values: [10, 20]),
                ActionParameter("amount", values: [100, 200])
            ]) {
                value.becomes(1)
            }
        }
    }

}

@TLAModel
struct EndToEndThreeParameterActionMachine {
    static var spec: TLASpec {
        TLASpec("EndToEndThreeParameterActionMachine") {
            let value = Var<Int>("value")
            let source = Expr<Int>(.variable("source"))
            let destination = Expr<Int>(.variable("destination"))
            let amount = Expr<Int>(.variable("amount"))
            Variable(value, 0)
            SwiftTLA.Action("transfer", parameters: [
                ActionParameter("source", values: [1, 2]),
                ActionParameter("destination", values: [10, 20]),
                ActionParameter("amount", values: [100, 200])
            ]) {
                value.becomes(source + destination + amount)
            }
        }
    }
}

@TLAModel
struct NondeterministicConstrainedMachine {
    static var spec: TLASpec {
        TLASpec("NondeterministicConstrainedMachine") {
            let value = Var<Int>("value")
            Variable(value, 0)
            SwiftTLA.Action("choose") {
                ActionExpr.exists("selected", from: StateExpr.set([1, 2, 3])) { selected in
                    value.becomes(Expr<Int>(selected))
                }
            }
            Constraint(value <= 2)
            Invariant("WithinBound") { value <= 3 }
        }
    }
}

@TLAModel
struct NestedComposedCounter {
    static var spec: TLASpec {
        TLASpec("NestedComposedCounter") {
            let count = Var<Int>("count")
            Variable(count, 0)
            SwiftTLA.Action("advance") { count.becomes(count + 1).when(count < 2) }
        }
    }

}
