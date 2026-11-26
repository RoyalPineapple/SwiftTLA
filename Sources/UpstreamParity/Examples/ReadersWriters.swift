// Multiple readers may share access while a writer needs exclusive access.
// https://github.com/tlaplus/Examples/blob/ceeaa904140e3e03781cb2a79cd6c6d8b8b08e10/specifications/ReadersWriters/ReadersWriters.tla

import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct ReadersWritersModel {
    @TLATuple
    package struct Request: Hashable, Sendable {
        package let kind: String
        package let actor: Int
    }

    package enum Step: String, CaseIterable {
        case enqueueReadRequest = "TryRead"
        case enqueueWriteRequest = "TryWrite"
        case grantNextRequest = "ReadOrWrite"
        case releaseAnyActiveActor = "Stop"
        case releaseActor = "StopActivity"
    }

    package static var spec: TLASpec {
        #spec("ReadersWriters") { scope in
            Extends(.finiteSets, .naturals, .sequences)
            let actorCount = scope.parameter(tlaName: "NumActors", as: Int.self, in: 3...3)
            // The AP instance exposes StopActivity(actor); MC observes the enclosing Stop action.
            let exposeStoppingActor = scope.parameter(as: Bool.self)
            let actors = IntRange(1, through: actorCount)
            let readers = scope.sharedVar(initial: Set<Int>())
            let writers = scope.sharedVar(initial: Set<Int>())
            let requestQueue = scope.sharedVar(tlaName: "waiting", initial: Array<Request>([]))

            let enqueueReadRequest = Do(Step.enqueueReadRequest, over: actors) { actor in
                let request = Request.expression(kind: "read", actor: actor)
                When(!requestQueue.contains(request))
                requestQueue.append(request)
            }
            let enqueueWriteRequest = Do(Step.enqueueWriteRequest, over: actors) { actor in
                let request = Request.expression(kind: "write", actor: actor)
                When(!requestQueue.contains(request))
                requestQueue.append(request)
            }
            let grantNextRequest = Do(Step.grantNextRequest, when: !requestQueue.isEmpty && writers.isEmpty) {
                let request = requestQueue.head()
                If(request.kind == "read") {
                    readers.insert(request.actor)
                } else: {
                    When(request.kind == "write" && readers.isEmpty)
                    writers.insert(request.actor)
                }
                requestQueue.set(requestQueue.tail())
            }
            let finishActivity = Macro { (actor: MacroParameter<Int>) in
                If(readers.contains(actor)) {
                    readers.remove(actor)
                } else: {
                    writers.remove(actor)
                }
            }
            let releaseAnyActiveActor = Do(Step.releaseAnyActiveActor, when: !exposeStoppingActor) {
                With(readers.union(writers)) { actor in
                    finishActivity(actor)
                }
            }
            Do(Step.releaseActor, over: actors) { actor in
                When(exposeStoppingActor && (readers.contains(actor) || writers.contains(actor)))
                finishActivity(actor)
            }

            WeakFairness(each: enqueueReadRequest)
            WeakFairness(each: enqueueWriteRequest)
            WeakFairness(grantNextRequest)
            WeakFairness(releaseAnyActiveActor)

            let typeOK = Invariant("TypeOK")
            typeOK {
                readers.isSubset(of: actors)
                writers.isSubset(of: actors)
                requestQueue.allSatisfy { request in
                    (request.kind == "read" || request.kind == "write")
                        && actors.contains(request.actor)
                }
            }
            let safety = Invariant("Safety")
            safety {
                readers.isEmpty || writers.isEmpty
                writers.count <= 1
            }
            let Liveness = Temporal()
            Liveness(forEach: actors) { actor in .all([
                .alwaysEventually(readers.contains(actor)), .alwaysEventually(writers.contains(actor)),
                .alwaysEventually(!readers.contains(actor)), .alwaysEventually(!writers.contains(actor)),
            ]) }

            Validation("APReadersWriters") {
                Bind(actorCount, to: 3)
                Bind(exposeStoppingActor, to: true)
            }.behavior(.initialAndNext).checking(only: [safety])
            Validation("MC") {
                Bind(actorCount, to: 3)
                Bind(exposeStoppingActor, to: false)
            }.checking(only: [typeOK, safety, Liveness])
        }
    }
}
