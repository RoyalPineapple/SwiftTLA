import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct ReadersWritersModel {
    package enum Step: String, CaseIterable {
        case tryRead = "TryRead", tryWrite = "TryWrite", readOrWrite = "ReadOrWrite"
        case stop = "Stop", stopActivity = "StopActivity"
    }

    package static var spec: TLASpec {
        #spec("ReadersWriters") { scope in
            Extends(.finiteSets, .naturals, .sequences)
            let NumActors = scope.parameter(as: Int.self, in: 3...3)
            // The AP instance exposes StopActivity(actor); MC observes the enclosing Stop action.
            let exposeStoppingActor = scope.parameter(as: Bool.self)
            let actors = IntRange(1, through: NumActors)
            let readers = scope.sharedVar(initial: Set<Int>())
            let writers = scope.sharedVar(initial: Set<Int>())
            let waiting = scope.sharedVar(initial: Array<Pair<String, Int>>([]))

            let tryRead = Do(Step.tryRead, over: actors) { actor in
                let request = Pair<String, Int>.literal("read", actor)
                When(!waiting.contains(request))
                waiting.append(request)
            }
            tryRead
            let tryWrite = Do(Step.tryWrite, over: actors) { actor in
                let request = Pair<String, Int>.literal("write", actor)
                When(!waiting.contains(request))
                waiting.append(request)
            }
            tryWrite
            let readOrWrite = Do(Step.readOrWrite, when: !waiting.isEmpty && writers.isEmpty) {
                let request = waiting.head()
                If(request.first() == "read") {
                    readers.insert(request.second())
                } else: {
                    When(request.first() == "write" && readers.isEmpty)
                    writers.insert(request.second())
                }
                waiting.set(waiting.tail())
            }
            readOrWrite
            let finishActivity = Macro { (actor: MacroParameter<Int>) in
                If(readers.contains(actor)) {
                    readers.remove(actor)
                } else: {
                    writers.remove(actor)
                }
            }
            let stop = Do(Step.stop, when: !exposeStoppingActor) {
                With(readers.union(writers)) { actor in
                    finishActivity(actor)
                }
            }
            stop
            Do(Step.stopActivity, over: actors) { actor in
                When(exposeStoppingActor && (readers.contains(actor) || writers.contains(actor)))
                finishActivity(actor)
            }

            WeakFairness(each: tryRead)
            WeakFairness(each: tryWrite)
            WeakFairness(readOrWrite)
            WeakFairness(stop)

            let typeOK = Invariant("TypeOK") {
                readers.isSubset(of: actors)
                writers.isSubset(of: actors)
                IntRange(1, through: waiting.count).allSatisfy { i in
                    let request = waiting[i]
                    return (request.first() == "read" || request.first() == "write")
                        && actors.contains(request.second())
                }
            }
            typeOK
            let safety = Invariant("Safety") {
                readers.isEmpty || writers.isEmpty
                writers.count <= 1
            }
            safety
            let Liveness = Temporal()
            Liveness(forEach: actors) { actor in .all([
                .alwaysEventually(readers.contains(actor)), .alwaysEventually(writers.contains(actor)),
                .alwaysEventually(!readers.contains(actor)), .alwaysEventually(!writers.contains(actor)),
            ]) }

            Validation("APReadersWriters") {
                Bind(NumActors, to: 3)
                Bind(exposeStoppingActor, to: true)
            }.behavior(.initialAndNext).checking(only: [safety])
            Validation("MC") {
                Bind(NumActors, to: 3)
                Bind(exposeStoppingActor, to: false)
            }.checking(only: [typeOK, safety, Liveness])
        }
    }
}
