import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct SelectedRecordAction {
    struct Packet: Hashable, Sendable {
        let count: Int
        let ready: Bool

        static func == (lhs: Self, rhs: Self) -> Bool { lhs.ready == rhs.ready }
        func hash(into hasher: inout Hasher) { hasher.combine(ready) }
    }

    enum Step: String, CaseIterable { case write, probe }

    static var spec: TLASpec {
        #spec("SelectedRecordAction") { scope in
            let query = scope.sharedVar(initial: Packet(count: 3, ready: false))
            let seen = scope.sharedVar(initial: false)
            let write = Do(Step.write, over: SetExpr<Packet>.literal(Packet(count: 1, ready: false))) { packet in
                query.set(packet)
            }
            Do(Step.probe) {
                When(write.isEnabled(for: query))
                seen.set(true)
            }
            Invariant("CanWrite") { write.isEnabled(for: query) }
        }
    }
}

@TLAModel
struct NestedSetActionDomain {
    enum Step: String, CaseIterable { case select, reset }

    static var spec: TLASpec {
        #spec("NestedSetActionDomain") { scope in
            let limit = scope.parameter(as: Int.self, in: 1...3)
            let value = scope.sharedVar(initial: 0)
            let base = IntRange(1, through: limit)
            let union4 = base.union(base).union(base).union(base).union(base)
            let union8 = union4.union(base).union(base).union(base).union(base)
            let union12 = union8.union(base).union(base).union(base).union(base)
            let union16 = union12.union(base).union(base).union(base).union(base)
            let union20 = union16.union(base).union(base).union(base).union(base)
            let union24 = union20.union(base).union(base).union(base).union(base)
            let low = IntRange(1, through: 2)
            let middle = IntRange(2, through: 2)
            let domain = union24.intersection(base).subtracting(low.subtracting(middle))
            Do(Step.select, over: domain) { item in value.set(item) }
            Do(Step.reset) { value.set(0) }
        }
    }
}
