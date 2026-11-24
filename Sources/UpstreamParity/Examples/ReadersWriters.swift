import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct ReadersWritersModel {
    package enum Step: String, CaseIterable {
        case tryRead = "TryRead", tryWrite = "TryWrite", readOrWrite = "ReadOrWrite", stop = "Stop"
    }

    package static var spec: TLASpec {
        #spec("ReadersWriters") { scope in
            Extends(.finiteSets, .naturals, .sequences)
            let NumActors = scope.parameter(as: Int.self, in: 3...3)
            let actors = IntRange(1, through: NumActors)
            let readers = scope.sharedVar(initial: Set<Int>())
            let writers = scope.sharedVar(initial: Set<Int>())
            let waiting = scope.sharedVar(initial: Array<Pair<String, Int>>([]))

            let tryRead = Do(Step.tryRead, over: actors) { actor in
                let request = Pair<String, Int>.literal("read", actor)
                When(!IntRange(1, through: waiting.count).contains { i in waiting[i] == request })
                waiting.append(request)
            }
            tryRead
            let tryWrite = Do(Step.tryWrite, over: actors) { actor in
                let request = Pair<String, Int>.literal("write", actor)
                When(!IntRange(1, through: waiting.count).contains { i in waiting[i] == request })
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
            let stop = Do(Step.stop) {
                With(readers.union(writers)) { actor in
                    If(readers.contains(actor)) {
                        readers.remove(actor)
                    } else: {
                        writers.remove(actor)
                    }
                }
            }
            stop

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

            let APReadersWriters = Validation { Bind(NumActors, to: 3) }
                .behavior(.initialAndNext).checking(only: [safety])
            APReadersWriters
            let MC = Validation { Bind(NumActors, to: 3) }.checking(only: [typeOK, safety, Liveness])
            MC
        }
    }
}
