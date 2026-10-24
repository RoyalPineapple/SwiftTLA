import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct OrderedAlgorithmCopyProofModel {
    enum Step: String, CaseIterable { case copy }

    static var spec: TLASpec {
        #spec("OrderedAlgorithmCopyProofModel") {
            let algorithm = Algorithm(label: "OrderedAlgorithmCopyProofModel", scoped: { scope in
                let first = scope.sharedVar(_name: "first", initial: 1)
                let second = scope.sharedVar(_name: "second", initial: 2)
                While(Step.copy, true) {
                    Assign(first, to: second)
                    Assign(second, to: first)
                }
            })
            algorithm
        }
    }
}

@TLAModel
struct SequentialCopyProofModel {
    enum Step: String, CaseIterable { case copy, finish }

    static var spec: TLASpec {
        #spec("SequentialCopyProofModel") {
            let algorithm = Algorithm(label: "SequentialCopyProofModel", scoped: { scope in
                let first = scope.sharedVar(_name: "first", initial: 1)
                let second = scope.sharedVar(_name: "second", initial: 2)
                Do(Step.copy) {
                    Assign(first, to: second)
                    Assign(second, to: first)
                }
                Do(Step.finish) {
                    Assign(first, to: 1)
                    Assign(second, to: 2)
                }
            })
            algorithm
        }
    }
}

@TLAModel
struct SequentialDependentIntInitialProofModel {
    enum Step: String, CaseIterable { case advance }

    static var spec: TLASpec {
        #spec("SequentialDependentIntInitialProofModel") {
            let algorithm = Algorithm(scoped: { scope in
                let first = scope.sharedVar(initial: 1)
                let second = scope.sharedVar(initial: (first + 2) + 1)
                Do(Step.advance) {
                    Assign(first, to: second + 1)
                }
            })
            algorithm
        }
    }
}

@TLAModel
struct OrderedCopyModel {
    enum Step: String, CaseIterable { case copy, repeatWrites }

    static var spec: TLASpec {
        #spec("OrderedCopy") {
            let orderedCopy = Algorithm(label: "OrderedCopy", scoped: { scope in
                let x = scope.sharedVar(initial: 1)
                let y = scope.sharedVar(initial: 0)
                Do(Step.copy) {
                    Assign(x, to: x + 1)
                    Assign(y, to: x)
                }
                Do(Step.repeatWrites) {
                    Assign(x, to: x + 1)
                    Assign(x, to: x + 1)
                }
            })
            orderedCopy
        }
    }
}

@TLAModel
struct OrderedOverflowModel {
    enum Step: String, CaseIterable { case advance }

    static var spec: TLASpec {
        #spec("OrderedOverflow") {
            let algorithm = Algorithm(label: "OrderedOverflow", scoped: { scope in
                let count = scope.sharedVar(initial: 9_223_372_036_854_775_806)
                Do(Step.advance) {
                    Assign(count, to: count + 1)
                    Assign(count, to: count + 1)
                }
            })
            algorithm
        }
    }
}

@TLAModel
struct NestedAdditionOverflowModel {
    enum Step: String, CaseIterable { case advance }

    static var spec: TLASpec {
        #spec("NestedAdditionOverflow") {
            let algorithm = Algorithm(label: "NestedAdditionOverflow", scoped: { scope in
                let count = scope.sharedVar(initial: 9_223_372_036_854_775_806)
                Do(Step.advance) {
                    Assign(count, to: (count + 1) + 1)
                }
            })
            algorithm
        }
    }
}

@TLAModel
struct OrderedGuardModel {
    enum Step: String, CaseIterable { case choose }

    static var spec: TLASpec {
        #spec("OrderedGuard") {
            let orderedGuard = Algorithm(label: "OrderedGuard", scoped: { scope in
                let value = scope.sharedVar(_name: "value", initial: 0)
                let copied = scope.sharedVar(_name: "copied", initial: 0)
                Do(Step.choose) {
                    Assign(value, to: 1)
                    Choose(1...2) { candidate in
                        When(candidate > value)
                        Assign(value, to: candidate)
                    }
                    Assign(copied, to: value)
                }
            })
            orderedGuard
        }
    }
}

@TLAModel
struct OrderedBlockedModel {
    enum Step: String, CaseIterable { case advance }

    static var spec: TLASpec {
        #spec("OrderedBlocked") {
            let orderedBlocked = Algorithm(label: "OrderedBlocked", scoped: { scope in
                let value = scope.sharedVar(_name: "value", initial: 0)
                Do(Step.advance) {
                    Assign(value, to: 1)
                    When(value == 0)
                    Assign(value, to: 2)
                }
            })
            orderedBlocked
        }
    }
}

@TLAModel
struct OrderedAssertionModel {
    enum Step: String, CaseIterable { case advance }

    static var spec: TLASpec {
        #spec("OrderedAssertion") {
            let orderedAssertion = Algorithm(label: "OrderedAssertion", scoped: { scope in
                let value = scope.sharedVar(_name: "value", initial: 0)
                Do(Step.advance) {
                    Assign(value, to: 1)
                    Assert(value == 1)
                }
            })
            orderedAssertion
        }
    }
}

@TLAModel
struct FailingAssertionModel {
    enum Step: String, CaseIterable { case check }

    static var spec: TLASpec {
        #spec("FailingAssertion") { scope in
            let value = scope.sharedVar(_name: "value", initial: 0)
            let algorithm = Algorithm(label: "Check") {
                Do(Step.check) {
                    Assert(value == 1)
                    Stop()
                }
            }
            algorithm
        }
    }
}

@TLAModel
struct SavedStepValueModel {
    enum Step: String, CaseIterable { case advance }

    static var spec: TLASpec {
        #spec("SavedStepValue") {
            let savedStepValue = Algorithm(label: "SavedStepValue", scoped: { scope in
                let count = scope.sharedVar(_name: "count", initial: 1)
                let copied = scope.sharedVar(_name: "copied", initial: 0)
                Do(Step.advance) {
                    Assign(count, to: 2)
                    let saved: Expr<Int> = count.expr
                    Assign(count, to: 3)
                    If(count == 3) {
                        let saved = saved + 1
                        Assign(count, to: 4)
                        Assign(copied, to: saved)
                    } else: {
                        Assign(copied, to: -1)
                    }
                    Assert(saved == 2)
                }
            })
            savedStepValue
        }
    }
}
