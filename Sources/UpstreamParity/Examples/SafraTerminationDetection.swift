// Safra's token collects signed message counts around a ring to detect distributed termination.
// https://github.com/tlaplus/Examples/blob/ceeaa904140e3e03781cb2a79cd6c6d8b8b08e10/specifications/ewd998/EWD998.tla

import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct SafraTerminationDetectionModel: Sendable {
    package struct Token: Hashable, Sendable {
        package let pos: Int
        package let q: Int
        package let color: String
    }

    private enum Step: String, CaseIterable {
        case initiateProbe = "InitiateProbe"
        case passToken = "PassToken"
        case sendMessage = "SendMsg"
        case receiveMessage = "RecvMsg"
        case deactivate = "Deactivate"
    }

    package static var spec: TLASpec {
        #spec("EWD998") { scope in
            Import(FunctionsModule.module)
            let N = scope.parameter(as: Int.self, in: Int.all)
            Assume(N > 0)
            let nodes = 0..<N
            let colors = Set<String>(["white", "black"])
            let zeroCounts = Dictionary<Int, Int>.mapping(over: nodes) { _ in 0 }
            let active: SharedVariable<[Int: Bool]> = scope.sharedVar(initiallyIn: Functions(from: nodes, to: Bool.all))
            let color: SharedVariable<[Int: String]> = scope.sharedVar(initiallyIn: Functions(from: nodes, to: colors))
            let counter = scope.sharedVar(initial: zeroCounts)
            let pending = scope.sharedVar(initial: zeroCounts)
            let initialTokens = nodes.mapping { position in Token.expression(pos: position, q: 0, color: "black") }
            let token: SharedVariable<Token> = scope.sharedVar(initiallyIn: initialTokens)

            let initiate = Do(Step.initiateProbe, when: token.pos == 0
                && (token.color == "black" || color[0] == "black" || counter[0] + token.q > 0)) {
                token.set(Token.expression(pos: N - 1, q: 0, color: "white"))
                color[0].set("white")
            }
            let pass = Do(Step.passToken, over: IntRange(1, through: N - 1)) { node in
                When(!active[node] && token.pos == node)
                token.set(Token.expression(pos: node - 1, q: token.q + counter[node],
                    color: If(color[node] == "black", then: "black", else: token.color)))
                color[node].set("white")
            }
            WeakFairness(anyOf: [initiate, pass])

            Do(Step.sendMessage, over: nodes) { sender in
                When(active[sender])
                With(nodes) { recipient in
                    When(recipient != sender)
                    counter[sender] += 1
                    pending[recipient] += 1
                }
            }
            Do(Step.receiveMessage, over: nodes) { recipient in
                When(pending[recipient] > 0)
                pending[recipient].set(pending[recipient] - 1)
                counter[recipient].set(counter[recipient] - 1)
                color[recipient].set("black")
                active[recipient].set(true)
            }
            Do(Step.deactivate, over: nodes) { node in
                When(active[node])
                active[node].set(false)
            }

            Constraint(token.q <= 9 && nodes.allSatisfy { node in counter[node] <= 3 && pending[node] <= 3 })
            Invariant("TypeOK") {
                Functions(from: nodes, to: Bool.all).contains(active)
                    && Functions(from: nodes, to: colors).contains(color)
                    && Functions(from: nodes, to: Int.all).contains(counter)
                    && pending.keys == nodes && nodes.allSatisfy { node in pending[node] >= 0 }
                    && nodes.contains(token.pos) && Int.all.contains(token.q) && colors.contains(token.color)
            }
            let inFlight = Sum(pending, over: nodes)
            let detected = token.pos == 0 && token.color == "white" && token.q + counter[0] == 0
                && color[0] == "white" && !active[0]
            Invariant("TerminationDetection") {
                !detected || (inFlight == 0 && nodes.allSatisfy { node in !active[node] })
            }
            let passedNodes = IntRange(token.pos + 1, through: N - 1)
            let remainingNodes = IntRange(0, through: token.pos)
            Invariant("Inv") {
                inFlight == Sum(counter, over: nodes)
                (passedNodes.allSatisfy { node in !active[node] }
                    && token.q == If(token.pos == N - 1, then: 0, else: Sum(counter, over: passedNodes)))
                    || Sum(counter, over: remainingNodes) + token.q > 0
                    || remainingNodes.contains { node in color[node] == "black" }
                    || token.color == "black"
            }

            Validation("Small") { Bind(N, to: 3) }
                .checkingDeadlock(false)
        }
    }
}
