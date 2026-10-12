import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct IncreasingSelection {
    enum Step: String, CaseIterable { case advance }

    static var spec: TLASpec {
        #spec {
            let increasingSelection = Algorithm(label: "IncreasingSelection", scoped: { scope in
                let position = scope.sharedVar(initial: 0)
                While(Step.advance, true) {
                    Assign(position, to: Select(from: Set<Int>([1, 2, 3])) { candidate in
                        candidate.expr > position
                    })
                }
            })
            increasingSelection
        }
    }
}

@TLAModel
struct ClosedMissingSelection {
    enum Step: String, CaseIterable { case advance }

    static var spec: TLASpec {
        #spec {
            let closedMissingSelection = Algorithm(scoped: { scope in
                let position = scope.sharedVar(initial: 0)
                Do(Step.advance) {
                    Assign(position, to: Select(from: Set<Int>([1])) { _ in false })
                }
            })
            closedMissingSelection
        }
    }
}

@TLAModel
struct MissingStringSelection {
    enum Step: String, CaseIterable { case select }

    static var spec: TLASpec {
        #spec {
            let missingStringSelection = Algorithm(scoped: { scope in
                let selected = scope.sharedVar(initial: "none")
                Do(Step.select) {
                    Assign(selected, to: Select(from: Set<String>(["alpha"])) { _ in false })
                }
            })
            missingStringSelection
        }
    }
}

@TLAModel
struct NestedMissingSelection {
    enum Step: String, CaseIterable { case advance }

    static var spec: TLASpec {
        #spec {
            let nestedMissingSelection = Algorithm(scoped: { scope in
                let position = scope.sharedVar(initial: 0)
                Do(Step.advance) {
                    Assign(position, to: Select(from: Set<Int>([1])) { _ in false } + 1)
                }
            })
            nestedMissingSelection
        }
    }
}

@TLAModel
struct AggregateMissingSelection {
    enum Step: String, CaseIterable { case select }

    static var spec: TLASpec {
        #spec("AggregateMissingSelection") { scope in
            let selected = scope.sharedVar(initial: TupleExpr<Int>())
            Do(Step.select) {
                Assign(selected, to: TupleExpr<Int>.literal(
                    Select(from: Set<Int>([1])) { _ in false }, 0
                ))
            }
        }
    }
}

@TLAModel
struct NestedOverflowSelection {
    enum Step: String, CaseIterable { case advance }

    static var spec: TLASpec {
        #spec {
            let nestedOverflowSelection = Algorithm(scoped: { scope in
                let position = scope.sharedVar(initial: 0)
                Do(Step.advance) {
                    Assign(position, to: Select(from: Set<Int>([9_223_372_036_854_775_807])) { _ in true } + 1)
                }
            })
            nestedOverflowSelection
        }
    }
}

@TLAModel
struct BooleanSelection {
    enum Step: String, CaseIterable { case select }

    static var spec: TLASpec {
        #spec("BooleanSelection") { scope in
            let booleanSelection = Algorithm(scoped: { scope in
                let flag = scope.sharedVar(initial: true)
                Do(Step.select) {
                    Assign(flag, to: Select(from: Set<Bool>([true, false])) { _ in true })
                }
            })
            booleanSelection
        }
    }
}

@TLAModel
struct EnumSelection {
    enum Mode: String, CaseIterable, FiniteTLAValueDomain {
        case zed, alpha
        static var defaultValue: Self { .zed }
        static let finiteValues = allCases
    }
    enum Step: String, CaseIterable { case select }

    static var spec: TLASpec {
        #spec {
            let enumSelection = Algorithm(scoped: { scope in
                let selected = scope.sharedVar(initial: Mode.zed)
                Do(Step.select) {
                    Assign(selected, to: Select(from: Mode.all) { _ in true })
                }
            })
            enumSelection
        }
    }
}

@TLAModel
struct StringSelection {
    enum Step: String, CaseIterable { case select }

    static var spec: TLASpec {
        #spec {
            let stringSelection = Algorithm(scoped: { scope in
                let selected = scope.sharedVar(initial: "zed")
                Do(Step.select) {
                    Assign(selected, to: Select(from: Set<String>(["zed", "alpha"])) { _ in true })
                }
            })
            stringSelection
        }
    }
}

@TLAModel
struct SequenceSelection {
    enum Step: String, CaseIterable { case select }

    static var spec: TLASpec {
        #spec {
            let sequenceSelection = Algorithm(scoped: { scope in
                let selected = scope.sharedVar(initial: [2])
                Do(Step.select) {
                    Assign(selected, to: Select(from: Set<[Int]>([[2], [1, 0], [1]])) { _ in true })
                }
            })
            sequenceSelection
        }
    }
}

@TLAModel
struct ConditionalSelectionFailure {
    enum Step: String, CaseIterable { case select }

    static var spec: TLASpec {
        #spec {
            let conditionalSelectionFailure = Algorithm(scoped: { scope in
                let attempt = scope.sharedVar(in: SetExpr<Bool>.literal(false, true))
                let selected = scope.sharedVar(initial: 0)
                Do(Step.select) {
                    If(attempt) {
                        Assign(selected, to: Select(from: Set<Int>([1])) { _ in false })
                    } else: {
                        Assign(selected, to: 2)
                    }
                }
            })
            conditionalSelectionFailure
        }
    }
}

@TLAModel
struct ConditionalChoiceConditionFailure {
    enum Step: String, CaseIterable { case select }

    static var spec: TLASpec {
        #spec {
            let conditionalChoiceConditionFailure = Algorithm(scoped: { scope in
                let selected = scope.sharedVar(initial: 0)
                Do(Step.select) {
                    If(Select(from: Set<Bool>([true])) { _ in false }) {
                        Assign(selected, to: 1)
                    } else: {
                        Assign(selected, to: 2)
                    }
                }
            })
            conditionalChoiceConditionFailure
        }
    }
}

@TLAModel
struct DynamicSequenceSelection {
    enum Step: String, CaseIterable { case select }

    static var spec: TLASpec {
        #spec {
            let dynamicSequenceSelection = Algorithm(scoped: { scope in
                let candidates = scope.sharedVar(initial: Set<[Int]>([[2], [1, 0], [1]]))
                let selected = scope.sharedVar(initial: [2])
                Do(Step.select) {
                    Assign(selected, to: Select(from: candidates) { _ in true })
                }
            })
            dynamicSequenceSelection
        }
    }
}
