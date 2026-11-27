import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct Pulse {
    package enum Step: String, CaseIterable { case increment, blocked, fail }
    package static var spec: TLASpec {
        #spec("Pulse") { scope in
            let count = scope.sharedVar(initial: 0)
            let zero = scope.sharedVar(initial: 0)
            Do(Step.increment) { count.set(count + 1) }
            Do(Step.blocked, when: count < 0) { count.set(0) }
            Do(Step.fail) { count.set(1 / zero) }
        }
    }
}

@TLAModel
package struct Inventory {
    package enum Step: String, CaseIterable { case touch, increment, append }
    package static var spec: TLASpec {
        #spec("Inventory") { scope in
            let size = scope.parameter(as: Int.self, in: 1...65536)
            let counts = scope.sharedVar(initial: Dictionary<Int, Int>.mapping(over: IntRange(1, through: size)) { _ in 0 })
            let tick = scope.sharedVar(initial: 0)
            let queue = scope.sharedVar(initial: [Int]())
            Do(Step.touch) { counts[1].set(counts[1] + 1) }
            Do(Step.increment) { tick.set(tick + 1) }
            Do(Step.append) { queue.set(queue.appending(tick)) }
            Invariant("nonnegative") { counts[1] >= 0 }
        }
    }
}

@TLAModel
package struct Choices {
    package enum Step: String, CaseIterable { case pick }
    package static var spec: TLASpec {
        #spec("Choices") { scope in
            let size = scope.parameter(as: Int.self, in: 1...65536)
            let value = scope.sharedVar(initiallyIn: IntRange(1, through: size))
            Do(Step.pick) {
                With(IntRange(1, through: size)) { k in value.set(k.expr) }
            }
        }
    }
}
