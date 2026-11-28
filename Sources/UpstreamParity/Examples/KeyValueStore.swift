// Clients issue reads, inserts, and updates against the key-value interface of the B-tree
// example.
// https://github.com/tlaplus/Examples/blob/ceeaa904140e3e03781cb2a79cd6c6d8b8b08e10/specifications/btree/kvstore.tla

import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct KeyValueStoreModel: Sendable {
    package enum Atom: String, CaseIterable, FiniteTLAValueDomain {
        case a = "A", b = "B", c = "C"
        case x = "X", y = "Y", z = "Z", nilValue = "NIL"
        case missing, ok, error, get, insert, update, delete

        package static var defaultValue: Self { .nilValue }
        package static let finiteValues = allCases
        package var tlaValue: TLAValue {
            switch self {
            case .x, .y, .z, .nilValue: .constant(rawValue)
            case .a, .b, .c, .missing, .ok, .error, .get, .insert, .update, .delete: .string(rawValue)
            }
        }
    }

    package enum Phase: String, CaseIterable { case ready, working }
    package typealias Arguments = OneOf<Atom, [Atom]>
    private enum Step: String, CaseIterable {
        case getRequest = "GetReq", getResponse = "GetResp"
        case insertRequest = "InsertReq", insertResponse = "InsertResp"
        case updateRequest = "UpdateReq", updateResponse = "UpdateResp"
        case deleteRequest = "DeleteReq", deleteResponse = "DeleteResp"
    }

    package static var spec: TLASpec {
        #spec("kvstore") { scope in
            let Keys = scope.parameter(as: Set<Atom>.self, in: Set<Set<Atom>>([Set([.a, .b, .c])]))
            let Vals = scope.parameter(as: Set<Atom>.self, in: Set<Set<Atom>>([Set([.x, .y, .z])]))
            let NIL = scope.parameter(as: Atom.self, in: Set<Atom>([.nilValue]))
            let MISSING = scope.parameter(as: Atom.self, in: Set<Atom>([.missing]))
            let ops = Set<Atom>([.get, .insert, .delete, .update])
            Assume(!Vals.contains(MISSING))
            Assume(!Vals.contains(NIL) && !ops.contains(NIL) && NIL != MISSING)

            let op = scope.sharedVar(initial: NIL)
            let args = scope.sharedVar(initial: Arguments.first(NIL))
            let ret = scope.sharedVar(initial: NIL)
            let dict = scope.sharedVar(initial: Dictionary<Atom, Atom>.mapping(over: Keys) { _ in MISSING })
            let state = scope.sharedVar(initial: Phase.ready)
            let empty = [Atom]()
            let argv = args.assuming(Array<Atom>.self)

            Do(Step.getRequest, over: Keys) { key in
                When(state == Phase.ready)
                op.set(Atom.get)
                args.set(Arguments.second(empty.expr.appending(key)))
                ret.set(NIL)
                state.set(Phase.working)
            }
            Do(Step.getResponse) {
                When(op == Atom.get)
                ret.set(dict[argv[1]])
                state.set(Phase.ready)
            }
            Do(Step.insertRequest, over: Keys, Vals) { key, val in
                When(state == Phase.ready)
                op.set(Atom.insert)
                args.set(Arguments.second(empty.expr.appending(key).appending(val)))
                ret.set(NIL)
                state.set(Phase.working)
            }
            Do(Step.insertResponse) {
                When(op == Atom.insert && state == Phase.working)
                let absent = dict[argv[1]] == MISSING
                ret.set(If(absent, then: Atom.ok, else: Atom.error))
                dict[argv[1]].set(If(absent, then: argv[2], else: dict[argv[1]]))
                state.set(Phase.ready)
            }
            Do(Step.updateRequest, over: Keys, Vals) { key, val in
                When(state == Phase.ready)
                op.set(Atom.update)
                args.set(Arguments.second(empty.expr.appending(key).appending(val)))
                ret.set(NIL)
                state.set(Phase.working)
            }
            Do(Step.updateResponse) {
                When(op == Atom.update)
                let present = Vals.contains(dict[argv[1]])
                ret.set(If(present, then: Atom.ok, else: Atom.error))
                dict[argv[1]].set(If(present, then: argv[2], else: dict[argv[1]]))
                state.set(Phase.ready)
            }
            let deleteRequest = Do(Step.deleteRequest, over: Keys) { key in
                When(state == Phase.ready)
                op.set(Atom.delete)
                args.set(Arguments.second(empty.expr.appending(key)))
                ret.set(NIL)
                state.set(Phase.working)
            }
            Do(Step.deleteResponse) {
                When(op == Atom.delete)
                ret.set(Atom.ok)
                state.set(Phase.ready)
                dict[argv[1]].set(MISSING)
            }
            WeakFairness(deleteRequest, on: op)

            Invariant("TypeOK") {
                args == Arguments.first(NIL) || Keys.contains { key in
                    args == Arguments.second(empty.expr.appending(key)) || Vals.contains { val in
                        args == Arguments.second(empty.expr.appending(key).appending(val))
                    }
                }
                dict.keys == Keys
                Keys.allSatisfy { key in Vals.contains(dict[key]) || dict[key] == MISSING }
                ops.contains(op) || op == NIL
                Vals.contains(ret) || ret == Atom.ok || ret == Atom.error || ret == MISSING || ret == NIL
                state == Phase.ready || state == Phase.working
            }
            Validation("published") {
                Bind(Keys, to: Set<Atom>([.a, .b, .c]))
                Bind(Vals, to: Set<Atom>([.x, .y, .z]))
                Bind(NIL, to: Atom.nilValue)
                Bind(MISSING, to: Atom.missing)
            }
        }
    }
}
