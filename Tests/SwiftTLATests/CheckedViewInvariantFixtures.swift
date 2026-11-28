import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct CheckedViewInvariantMachine {
    enum Step: String, CaseIterable { case replace, zero }
    struct Entry: Hashable, Sendable { let id: Int; let limit: Int }
    typealias Slot = OneOf<Int, Entry>

    static var spec: TLASpec {
        #spec("CheckedViewInvariantMachine") { scope in
            let slot = scope.sharedVar(initial: Slot.second(Entry(id: 1, limit: 2)))
            Do(Step.replace) { slot.set(Slot.first(0)) }
            Do(Step.zero) { slot.set(Slot.second(Entry.expression(id: 0, limit: 2))) }
            Invariant("WithinLimit") {
                slot.expr.assuming(Entry.self).id == 1 && slot.expr.assuming(Entry.self).limit == 2
            }
            Invariant("ShortCircuit") {
                slot.expr == Slot.first(0) || slot.expr.assuming(Entry.self).limit == 2
            }
            Invariant("EarlierFailure") {
                5 / (slot.expr.assuming(Entry.self).id) == 5 && slot.expr.assuming(Entry.self).limit == 2
            }
        }
    }
}
