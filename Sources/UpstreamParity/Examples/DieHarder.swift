import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct DieHarderModel: Sendable {
    package enum Step: String, CaseIterable {
        case fillJug = "FillJug"
        case emptyJug = "EmptyJug"
        case jugToJug = "JugToJug"
    }

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
            Assume(Capacity.keys == Jug && Goal >= 0 && Jug.allSatisfy { j in Capacity[j] > 0 })
            Do(Step.fillJug, over: Jug) { j in contents[j].set(Capacity[j]) }
            Do(Step.emptyJug, over: Jug) { j in contents[j].set(0) }
            Do(Step.jugToJug, over: Jug, Jug) { j, k in
                When(j != k)
                If(contents[j] < Capacity[k] - contents[k]) {
                    let amountPoured = contents[j]
                    contents[j].set(0)
                    contents[k] += amountPoured
                } else: {
                    let amountPoured = Capacity[k] - contents[k]
                    contents[j].set(contents[j] - amountPoured)
                    contents[k].set(Capacity[k])
                }
            }
            let typeOK = Invariant("TypeOK") { contents.keys == Jug && Jug.allSatisfy { j in contents[j] >= 0 } }
            typeOK
            let notSolved = Invariant("NotSolved") { Jug.allSatisfy { j in contents[j] != Goal } }
            notSolved
            let MCDieHarder = Validation {
                Bind(Jug, to: Set<String>(["j1", "j2"]))
                Bind(Capacity, to: ["j1": 3, "j2": 5])
                Bind(Goal, to: 4)
            }.expect(notSolved, .violated)
            MCDieHarder
            let APDieHarder = Validation {
                Bind(Jug, to: Set<String>(["small_OF_JUG", "big_OF_JUG"]))
                Bind(Capacity, to: ["small_OF_JUG": 3, "big_OF_JUG": 5])
                Bind(Goal, to: 4)
            }.checking(only: [typeOK])
            APDieHarder
        }
    }
}
