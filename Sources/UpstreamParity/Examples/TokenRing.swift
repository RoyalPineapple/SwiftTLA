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
            let N = scope.parameter(as: Int.self, in: Int.all)
            let M = scope.parameter(as: Int.self, in: Int.all)
            Assume(N > 0)
            Assume(M > 0)
            Assume(N <= M + 1)

            let nodes = 0..<N
            let values = 0..<M
            let c: SharedVariable<[Int: Int]> = scope.sharedVar(initiallyIn: Functions(from: nodes, to: values))

            let createToken = Do(Step.createToken, when: c[0] == c[N - 1]) {
                c[0].set((c[N - 1] + 1) % M)
            }
            createToken
            let passToken = Do(Step.passToken, over: 1..<N) { i in
                When(c[i] != c[i - 1])
                c[i].set(c[i - 1])
            }
            passToken
            WeakFairness(anyOf: [createToken, passToken])

            Invariant("TypeOK") { Functions(from: nodes, to: values).contains(c) }
            let Stab = EventuallyAlways()
            let uniqueToken = IntRange(0, through: N).contains { split in
                (0..<split).allSatisfy { i in c[i] == c[0] }
                    && (split..<N).allSatisfy { i in c[i] == (c[0] - 1) % M }
            }
            Stab(uniqueToken)
            Validation("sixNodes") {
                Bind(N, to: 6)
                Bind(M, to: 6)
            }.checkingDeadlock(false)
        }
    }
}
