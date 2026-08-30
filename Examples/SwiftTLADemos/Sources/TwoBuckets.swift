import SwiftTLA
import SwiftTLAMacros

/// The Die Hard water-jug puzzle, expressed as a generated machine.
///
/// Each operation has one singleton process. This preserves the source model's
/// independent scheduling while exposing a clean Swift action surface such as
/// `try machine.send(.fillThree)`.
@TLAModel
public struct TwoBuckets {
    private enum FillThreeProcess: String, FiniteTLAValueDomain {
        case fillThree

        static var defaultValue: Self { .fillThree }
        static let finiteValues: [Self] = [.fillThree]

        var tlaValue: TLAValue { .string(rawValue) }
    }

    private enum FillFiveProcess: String, FiniteTLAValueDomain {
        case fillFive

        static var defaultValue: Self { .fillFive }
        static let finiteValues: [Self] = [.fillFive]

        var tlaValue: TLAValue { .string(rawValue) }
    }

    private enum EmptyThreeProcess: String, FiniteTLAValueDomain {
        case emptyThree

        static var defaultValue: Self { .emptyThree }
        static let finiteValues: [Self] = [.emptyThree]

        var tlaValue: TLAValue { .string(rawValue) }
    }

    private enum EmptyFiveProcess: String, FiniteTLAValueDomain {
        case emptyFive

        static var defaultValue: Self { .emptyFive }
        static let finiteValues: [Self] = [.emptyFive]

        var tlaValue: TLAValue { .string(rawValue) }
    }

    private enum PourThreeIntoFiveProcess: String, FiniteTLAValueDomain {
        case pourThreeIntoFive

        static var defaultValue: Self { .pourThreeIntoFive }
        static let finiteValues: [Self] = [.pourThreeIntoFive]

        var tlaValue: TLAValue { .string(rawValue) }
    }

    private enum PourFiveIntoThreeProcess: String, FiniteTLAValueDomain {
        case pourFiveIntoThree

        static var defaultValue: Self { .pourFiveIntoThree }
        static let finiteValues: [Self] = [.pourFiveIntoThree]

        var tlaValue: TLAValue { .string(rawValue) }
    }

    private enum Step: String, CaseIterable {
        case fillThree
        case fillFive
        case emptyThree
        case emptyFive
        case pourThreeIntoFive
        case pourFiveIntoThree
    }

    public static var spec: TLASpec {
        #spec("TwoBuckets") {
            Algorithm("TwoBuckets", scoped: { scope in
                let three = scope.sharedVar("three", initial: 0)
                let five = scope.sharedVar("five", initial: 0)

                Each(FillThreeProcess.all) { _ in
                    Do(Step.fillThree) {
                        When(three < 3)
                        Assign(three, to: 3)
                        Goto(Step.fillThree)
                    }
                }
                Each(FillFiveProcess.all) { _ in
                    Do(Step.fillFive) {
                        When(five < 5)
                        Assign(five, to: 5)
                        Goto(Step.fillFive)
                    }
                }
                Each(EmptyThreeProcess.all) { _ in
                    Do(Step.emptyThree) {
                        When(three > 0)
                        Assign(three, to: 0)
                        Goto(Step.emptyThree)
                    }
                }
                Each(EmptyFiveProcess.all) { _ in
                    Do(Step.emptyFive) {
                        When(five > 0)
                        Assign(five, to: 0)
                        Goto(Step.emptyFive)
                    }
                }
                Each(PourThreeIntoFiveProcess.all) { _ in
                    Do(Step.pourThreeIntoFive) {
                        When(three > 0 && five < 5)
                        Either {
                            When(three + five <= 5)
                            Assign(five, to: five + three)
                            Assign(three, to: 0)
                        } or: {
                            When(three + five > 5)
                            Assign(five, to: 5)
                            Assign(three, to: three - (5 - five))
                        }
                        Goto(Step.pourThreeIntoFive)
                    }
                }
                Each(PourFiveIntoThreeProcess.all) { _ in
                    Do(Step.pourFiveIntoThree) {
                        When(five > 0 && three < 3)
                        Either {
                            When(three + five <= 3)
                            Assign(three, to: three + five)
                            Assign(five, to: 0)
                        } or: {
                            When(three + five > 3)
                            Assign(three, to: 3)
                            Assign(five, to: five - (3 - three))
                        }
                        Goto(Step.pourFiveIntoThree)
                    }
                }

                Invariant("Capacity") {
                    three >= 0 && three <= 3
                    five >= 0 && five <= 5
                }
            })
        }
    }

}
