// Node zero creates a new token value and the other nodes copy their predecessor’s value.
// https://github.com/tlaplus/Examples/blob/ceeaa904140e3e03781cb2a79cd6c6d8b8b08e10/specifications/ewd426/TokenRing.tla

import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct TokenRingModel: Sendable {
    private enum Step: String, CaseIterable {
        case createToken = "CreateToken"
        case passToken = "PassToken"
    }

    package static var spec: TLASpec {
        #spec("TokenRing") { scope in
            Extends(.naturals, .finiteSets)
            let nodeCount = scope.parameter(tlaName: "N", as: Int.self, in: Int.all)
            let counterModulus = scope.parameter(tlaName: "M", as: Int.self, in: Int.all)
            Assume(nodeCount > 0)
            Assume(counterModulus > 0)
            Assume(nodeCount <= counterModulus + 1)

            let nodes = 0..<nodeCount
            let values = 0..<counterModulus
            let counters: SharedVariable<[Int: Int]> = scope.sharedVar(tlaName: "c", initiallyIn: Functions(from: nodes, to: values))

            let createToken = Do(Step.createToken, when: counters[0] == counters[nodeCount - 1]) {
                counters[0].set((counters[nodeCount - 1] + 1) % counterModulus)
            }
            let passToken = Do(Step.passToken, over: 1..<nodeCount) { i in
                When(counters[i] != counters[i - 1])
                counters[i].set(counters[i - 1])
            }
            WeakFairness(anyOf: [createToken, passToken])

            let typeOK = Invariant("TypeOK")
            typeOK { Functions(from: nodes, to: values).contains(counters) }
            let Stab = EventuallyAlways()
            let uniqueToken = IntRange(0, through: nodeCount).contains { split in
                (0..<split).allSatisfy { i in counters[i] == counters[0] }
                    && (split..<nodeCount).allSatisfy { i in counters[i] == (counters[0] - 1) % counterModulus }
            }
            Stab(uniqueToken)
            Validation("sixNodes") {
                Bind(nodeCount, to: 6)
                Bind(counterModulus, to: 6)
            }.checkingDeadlock(false)
            Validation("APTokenRing") {
                Bind(nodeCount, to: 6)
                Bind(counterModulus, to: 6)
            }.checking(only: [typeOK])
        }
    }
}
