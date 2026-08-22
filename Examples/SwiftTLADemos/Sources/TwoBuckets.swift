import SwiftTLA
import SwiftTLAMacros

/// The Die Hard water-jug puzzle, expressed as a generated formal machine.
///
/// Each operation has one singleton process. This preserves the formal model's
/// independent scheduling while exposing a clean Swift action surface such as
/// `try machine.apply(.fillThree)`.
@TLAModel
public struct TwoBuckets {
    private enum FillThreeProcess: String, FiniteDomainKey {
        case fillThree

        static var defaultValue: Self { .fillThree }
        static let formalDomain: [Self] = [.fillThree]
        static let formalTypeIdentity = FormalTypeIdentity(rawValue: "demos.two-buckets.fill-three")

        var tlaValue: TLAValue { .string(rawValue) }
    }

    private enum FillFiveProcess: String, FiniteDomainKey {
        case fillFive

        static var defaultValue: Self { .fillFive }
        static let formalDomain: [Self] = [.fillFive]
        static let formalTypeIdentity = FormalTypeIdentity(rawValue: "demos.two-buckets.fill-five")

        var tlaValue: TLAValue { .string(rawValue) }
    }

    private enum EmptyThreeProcess: String, FiniteDomainKey {
        case emptyThree

        static var defaultValue: Self { .emptyThree }
        static let formalDomain: [Self] = [.emptyThree]
        static let formalTypeIdentity = FormalTypeIdentity(rawValue: "demos.two-buckets.empty-three")

        var tlaValue: TLAValue { .string(rawValue) }
    }

    private enum EmptyFiveProcess: String, FiniteDomainKey {
        case emptyFive

        static var defaultValue: Self { .emptyFive }
        static let formalDomain: [Self] = [.emptyFive]
        static let formalTypeIdentity = FormalTypeIdentity(rawValue: "demos.two-buckets.empty-five")

        var tlaValue: TLAValue { .string(rawValue) }
    }

    private enum PourThreeIntoFiveProcess: String, FiniteDomainKey {
        case pourThreeIntoFive

        static var defaultValue: Self { .pourThreeIntoFive }
        static let formalDomain: [Self] = [.pourThreeIntoFive]
        static let formalTypeIdentity = FormalTypeIdentity(rawValue: "demos.two-buckets.pour-three-into-five")

        var tlaValue: TLAValue { .string(rawValue) }
    }

    private enum PourFiveIntoThreeProcess: String, FiniteDomainKey {
        case pourFiveIntoThree

        static var defaultValue: Self { .pourFiveIntoThree }
        static let formalDomain: [Self] = [.pourFiveIntoThree]
        static let formalTypeIdentity = FormalTypeIdentity(rawValue: "demos.two-buckets.pour-five-into-three")

        var tlaValue: TLAValue { .string(rawValue) }
    }

    private enum Step: String, PlusCalLabel, CaseIterable {
        case fillThree
        case fillFive
        case emptyThree
        case emptyFive
        case pourThreeIntoFive
        case pourFiveIntoThree
    }

    public static var spec: TLASpec {
        #spec("TwoBuckets") {
            Algorithm("TwoBuckets") { scope in
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
            }
        }
    }

    @TLAObservable
    public final class Observable {}
}
