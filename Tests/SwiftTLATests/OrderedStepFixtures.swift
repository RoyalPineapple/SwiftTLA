import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct OrderedCopyModel {
    enum Step: String, CaseIterable { case copy, repeatWrites }

    static var spec: TLASpec {
        #spec("OrderedCopy") {
            Algorithm("OrderedCopy", scoped: { scope in
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
        }
    }
}

@TLAModel
struct OrderedGuardModel {
    enum Step: String, CaseIterable { case choose }

    static var spec: TLASpec {
        #spec("OrderedGuard") {
            Algorithm("OrderedGuard", scoped: { scope in
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
        }
    }
}

@TLAModel
struct OrderedBlockedModel {
    enum Step: String, CaseIterable { case advance }

    static var spec: TLASpec {
        #spec("OrderedBlocked") {
            Algorithm("OrderedBlocked", scoped: { scope in
                let value = scope.sharedVar(_name: "value", initial: 0)
                Do(Step.advance) {
                    Assign(value, to: 1)
                    When(value == 0)
                    Assign(value, to: 2)
                }
            })
        }
    }
}

@TLAModel
struct OrderedAssertionModel {
    enum Step: String, CaseIterable { case advance }

    static var spec: TLASpec {
        #spec("OrderedAssertion") {
            Algorithm("OrderedAssertion", scoped: { scope in
                let value = scope.sharedVar(_name: "value", initial: 0)
                Do(Step.advance) {
                    Assign(value, to: 1)
                    Assert(value == 1)
                }
            })
        }
    }
}

@TLAModel
struct OrderedCallModel {
    enum Step: String, CaseIterable { case start, enter, finished }
    enum ProcedureName: String, CaseIterable { case copy }

    static var spec: TLASpec {
        #spec("OrderedCall") {
            Algorithm("OrderedCall", scoped: { scope in
                let input = scope.sharedVar(_name: "input", initial: 0)
                let output = scope.sharedVar(_name: "output", initial: 0)
                Procedure(ProcedureName.copy, parameters: Int.self) { value in
                    Do(Step.enter) {
                        Assign(output, to: value.expr)
                        Return()
                    }
                }
                Do(Step.start) {
                    Assign(input, to: 7)
                    Call(ProcedureName.copy, with: input.expr)
                }
                Do(Step.finished) { Stop() }
            })
        }
    }
}

@TLAModel
struct SavedStepValueModel {
    enum Step: String, CaseIterable { case advance }

    static var spec: TLASpec {
        #spec("SavedStepValue") {
            Algorithm("SavedStepValue", scoped: { scope in
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
        }
    }
}
