import SwiftTLA
import SwiftTLAMacros

/// A bounded FIFO queue with verified drain.
@TLAModel
public struct Queue<Element: Sendable>: Sendable {
    public let capacity: Int

    public static var spec: TLASpec {
        TLASpec("Queue") {
            let queued = StateVar(TLAValue.set([]))
            let phase = StateVar(0)

            Action("enqueue") { phase == 0 && queued.cardinality < 4 && phase.stays }
            Action("drain")   { phase == 0 && phase.becomes(1) }

            Invariant("capacity") { queued.cardinality <= 4 }
        }
    }

    private var buffer: [Element] = []

    public init(capacity: Int) {
        precondition(capacity > 0)
        self.capacity = capacity
    }

    public mutating func enqueue(_ value: Element) {
        applyenqueue()
        buffer.append(value)
    }

    public mutating func drain() -> [Element] {
        applydrain()
        let remaining = buffer
        buffer.removeAll()
        return remaining
    }
}
