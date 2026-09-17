import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct DieHarderModel: Sendable {
    package enum Step: String, CaseIterable { case FillJug, EmptyJug, JugToJug }

    package static var spec: TLASpec {
        #spec("DieHarder") { scope in
            Extends(.naturals)
            let Jug = scope.parameter(as: Set<String>.self, in: Set<Set<String>>([
                Set<String>(["j1", "j2"]), Set<String>(["small_OF_JUG", "big_OF_JUG"])
            ]))
            let Capacity = scope.parameter(as: [String: Int].self,
                in: Functions(from: Jug, to: Set<Int>([3, 5])))
            let Goal = scope.parameter(as: Int.self, in: Set<Int>([4]))
            let contents = scope.sharedVar(initial: Dictionary<String, Int>.mapping(over: Jug) { _ in 0 })
            let TypeOK = Invariant()
            let NotSolved = Invariant()
            Assume(Capacity.keys == Jug && Goal >= 0 && ForAll(in: Jug) { j in Capacity[j] > 0 })
            Do(Step.FillJug, over: Jug) { j in Assign(contents[j], to: Capacity[j]) }
            Do(Step.EmptyJug, over: Jug) { j in Assign(contents[j], to: 0) }
            Do(Step.JugToJug, over: Jug, Jug) { j, k in
                When(j != k)
                If(contents[j] < Capacity[k] - contents[k]) {
                    let amountPoured = contents[j]
                    Assign(contents[j], to: 0)
                    Assign(contents[k], to: contents[k] + amountPoured)
                } else: {
                    let amountPoured = Capacity[k] - contents[k]
                    Assign(contents[j], to: contents[j] - amountPoured)
                    Assign(contents[k], to: Capacity[k])
                }
            }
            TypeOK { contents.keys == Jug && ForAll(in: Jug) { j in contents[j] >= 0 } }
            NotSolved { ForAll(in: Jug) { j in contents[j] != Goal } }
            Validation("MCDieHarder") {
                Bind(Jug, to: Set<String>(["j1", "j2"]))
                Bind(Capacity, to: ["j1": 3, "j2": 5])
                Bind(Goal, to: 4)
            }.expect(NotSolved, .violated)
            Validation("APDieHarder") {
                Bind(Jug, to: Set<String>(["small_OF_JUG", "big_OF_JUG"]))
                Bind(Capacity, to: ["small_OF_JUG": 3, "big_OF_JUG": 5])
                Bind(Goal, to: 4)
            }.checking(only: [TypeOK])
        }
    }
}
