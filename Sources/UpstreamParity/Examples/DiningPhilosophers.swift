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

            Algorithm("DiningPhilosophers", scoped: { scope in
                let forks = scope.sharedVar("forks", initial: Function<Philosopher, Fork>.literal(
                    (Philosopher.one, Fork(holder: Philosopher.one, clean: false)),
                    (Philosopher.two, Fork(holder: Philosopher.one, clean: false)),
                    (Philosopher.three, Fork(holder: Philosopher.three, clean: false)),
                    (Philosopher.four, Fork(holder: Philosopher.four, clean: false)),
                    (Philosopher.five, Fork(holder: Philosopher.five, clean: false))
                ))

                Each(Philosopher.all, fairness: .weak, scoped: { philosopher, scope in
                    let hungry = scope.localVar("hungry", initial: true)

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
                                When(leftFork.holder == philosopher && leftFork.clean == false)
                                Assign(forks[philosopher].holder, to: left)
                                Assign(forks[philosopher].clean, to: true)
                            } or: {
                                Either {
                                    When(
                                        rightFork.holder == philosopher
                                            && rightFork.clean == false
                                            && !(leftFork.holder == philosopher && leftFork.clean == false)
                                    )
                                    Assign(forks[right].holder, to: right)
                                    Assign(forks[right].clean, to: true)
                                } or: {
                                    When(
                                        !(leftFork.holder == philosopher && leftFork.clean == false)
                                            && !(rightFork.holder == philosopher && rightFork.clean == false)
                                    )
                                }
                            }

                            Either {
                                When(canEat && hungry == true)
                                Goto(Step.eat)
                            } or: {
                                Either {
                                    When(!canEat && hungry == true)
                                    Goto(Step.loop)
                                } or: {
                                    When(hungry == false)
                                    Goto(Step.think)
                                }
                            }
                        }
                    }

                    Do(Step.think) {
                        Assign(hungry, to: true)
                        Goto(Step.loop)
                    }

                    Do(Step.eat) {
                        let right = If(philosopher == Philosopher.one, then: Philosopher.two, else:
                            If(philosopher == Philosopher.two, then: Philosopher.three, else:
                                If(philosopher == Philosopher.three, then: Philosopher.four, else:
                                    If(philosopher == Philosopher.four, then: Philosopher.five, else: Philosopher.one))))
                        Assign(hungry, to: false)
                        Assign(forks[philosopher].clean, to: false)
                        Assign(forks[right].clean, to: false)
                        Goto(Step.loop)
                    }

                    AlwaysEventually("NobodyStarves", !hungry)

                    Invariant("TypeOK") {
                        (forks[philosopher].holder == .one
                            || forks[philosopher].holder == .two
                            || forks[philosopher].holder == .three
                            || forks[philosopher].holder == .four
                            || forks[philosopher].holder == .five)
                            && (hungry == true || hungry == false)
                            && (At(Step.loop, philosopher) || At(Step.think, philosopher) || At(Step.eat, philosopher))
                    }
                })

                Invariant("ExclusiveAccess") {
                    ForAll(Philosopher.all) { first in
                        ForAll(Philosopher.all) { second in
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
            })
            Validation("NP5") {}
        }
    }
}
