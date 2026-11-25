import SwiftTLA
import SwiftTLAMacros

// Dining Philosophers — Chandy-Misra solution. NP=5.
// Upstream: specifications/DiningPhilosophers/DiningPhilosophers.tla

@TLAModel
package struct DiningPhilosophersModel: Sendable {
    package enum Philosopher: Int, FiniteTLAValueDomain {
        case one = 1
        case two = 2
        case three = 3
        case four = 4
        case five = 5

        package static var defaultValue: Self { .one }
        package static let finiteValues: [Self] = [.one, .two, .three, .four, .five]

        package var tlaValue: TLAValue { .int(rawValue) }
    }

    package struct Fork: Hashable, Sendable {
        let holder: Philosopher
        let clean: Bool
    }

    package enum Step: String, CaseIterable {
        case loop = "Loop"
        case think = "Think"
        case eat = "Eat"
    }

    package static var spec: TLASpec {
        #spec("DiningPhilosophers") {
            Extends(.integers)
            let TypeOK = Invariant()
            let ExclusiveAccess = Invariant()
            let NobodyStarves = AlwaysEventually()

            let DiningPhilosophers = Algorithm { scope in
                let forks = scope.sharedVar(initial: Function<Philosopher, Fork>.literal(
                    (Philosopher.one, Fork(holder: Philosopher.one, clean: false)),
                    (Philosopher.two, Fork(holder: Philosopher.one, clean: false)),
                    (Philosopher.three, Fork(holder: Philosopher.three, clean: false)),
                    (Philosopher.four, Fork(holder: Philosopher.four, clean: false)),
                    (Philosopher.five, Fork(holder: Philosopher.five, clean: false))
                ))

                Each(Philosopher.all, fairness: .weak) { philosopher, scope in
                    let hungry = scope.localVar(initial: true)

                    Do(Step.loop) {
                        let right = If(philosopher == Philosopher.one, then: Philosopher.two, else:
                            If(philosopher == Philosopher.two, then: Philosopher.three, else:
                                If(philosopher == Philosopher.three, then: Philosopher.four, else:
                                    If(philosopher == Philosopher.four, then: Philosopher.five, else: Philosopher.one))))
                        let left = If(philosopher == Philosopher.one, then: Philosopher.five, else:
                            If(philosopher == Philosopher.two, then: Philosopher.one, else:
                                If(philosopher == Philosopher.three, then: Philosopher.two, else:
                                    If(philosopher == Philosopher.four, then: Philosopher.three, else: Philosopher.four))))
                        let leftFork = forks[philosopher]
                        let rightFork = forks[right]
                        Let(leftFork.holder == philosopher
                            && rightFork.holder == philosopher
                            && leftFork.clean == true
                            && rightFork.clean == true) { canEat in

                            Either {
                                When(leftFork.holder == philosopher && leftFork.clean == false) {
                                    forks[philosopher].holder.set(left)
                                    forks[philosopher].clean.set(true)
                                }
                                When(
                                    rightFork.holder == philosopher
                                        && rightFork.clean == false
                                        && !(leftFork.holder == philosopher && leftFork.clean == false)
                                ) {
                                    forks[right].holder.set(right)
                                    forks[right].clean.set(true)
                                }
                                When(
                                    !(leftFork.holder == philosopher && leftFork.clean == false)
                                        && !(rightFork.holder == philosopher && rightFork.clean == false)
                                ) {}
                            }

                            Either {
                                When(canEat && hungry == true) {
                                    Goto(Step.eat)
                                }
                                When(!canEat && hungry == true) {
                                    Goto(Step.loop)
                                }
                                When(hungry == false) {
                                    Goto(Step.think)
                                }
                            }
                        }
                    }

                    Do(Step.think) {
                        hungry.set(true)
                        Goto(Step.loop)
                    }

                    Do(Step.eat) {
                        let right = If(philosopher == Philosopher.one, then: Philosopher.two, else:
                            If(philosopher == Philosopher.two, then: Philosopher.three, else:
                                If(philosopher == Philosopher.three, then: Philosopher.four, else:
                                    If(philosopher == Philosopher.four, then: Philosopher.five, else: Philosopher.one))))
                        hungry.set(false)
                        forks[philosopher].clean.set(false)
                        forks[right].clean.set(false)
                        Goto(Step.loop)
                    }

                    NobodyStarves(!hungry)

                    TypeOK {
                        (forks[philosopher].holder == .one
                            || forks[philosopher].holder == .two
                            || forks[philosopher].holder == .three
                            || forks[philosopher].holder == .four
                            || forks[philosopher].holder == .five)
                            && (hungry == true || hungry == false)
                            && philosopher.isAt(anyOf: Step.loop, .think, .eat)
                    }
                }

                ExclusiveAccess {
                    Philosopher.all.allSatisfy { first in
                        Philosopher.all.allSatisfy { second in
                            first == second
                                || !(At(Step.eat, first) && At(Step.eat, second)
                                    && ((first == Philosopher.one && second == Philosopher.two)
                                        || (first == Philosopher.two && second == Philosopher.three)
                                        || (first == Philosopher.three && second == Philosopher.four)
                                        || (first == Philosopher.four && second == Philosopher.five)
                                        || (first == Philosopher.five && second == Philosopher.one)))
                        }
                    }
                }
            }
            DiningPhilosophers
            Validation("NP5") {}
            Validation("apNP5", label: "AP NP5") {}
                .checking(only: [TypeOK, ExclusiveAccess])
                .behavior(.initialAndNext)
        }
    }
}
