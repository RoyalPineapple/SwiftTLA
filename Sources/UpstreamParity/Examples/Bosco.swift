// A process broadcasts its proposal, then counts distinct senders before deciding or passing a value to consensus.
// https://github.com/tlaplus/Examples/blob/ceeaa904140e3e03781cb2a79cd6c6d8b8b08e10/specifications/bosco/bosco.tla
// APbosco imports the same protocol and selects the same five invariants.
import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct BoscoModel: Sendable {
    @TLATuple
    package struct Vote: Hashable, Sendable {
        package let sender: Int
        package let echo: String
    }

    private enum Step: String, CaseIterable { case receiveAndAdvance = "Step" }

    package static var spec: TLASpec {
        #spec("bosco") { scope in
            let population = scope.parameter(tlaName: "N", as: Int.self, in: Int.all)
            let tolerance = scope.parameter(tlaName: "T", as: Int.self, in: Int.all)
            let faultyCount = scope.parameter(tlaName: "F", as: Int.self, in: Int.all)
            Assume(faultyCount >= 0 && tolerance >= faultyCount && population > 3 * tolerance)
            let decideAt = (population + 3 * tolerance) / 2 + 1
            let proposeAt = (population - tolerance) / 2 + 1
            let senders = IntRange(1, through: population)
            let correct = IntRange(1, through: population - faultyCount)
            let faulty = IntRange(population - faultyCount + 1, through: population)
            let echoes = Set<String>(["ECHO0", "ECHO1"])
            let messages = senders.flatMapping { sender in echoes.mapping { echo in Vote.expression(sender: sender, echo: echo) } }
            let byzantineVotes = faulty.flatMapping { sender in echoes.mapping { echo in Vote.expression(sender: sender, echo: echo) } }

            let phase: SharedVariable<[Int: String]> = scope.sharedVar(tlaName: "pc", initiallyIn: Functions(from: correct, to: Set<String>(["V0", "V1"])))
            let received = scope.sharedVar(tlaName: "rcvd", initial: Dictionary<Int, Set<Vote>>.mapping(over: correct) { _ in Set<Vote>() })
            let sent = scope.sharedVar(initial: Set<Vote>())

            Do(Step.receiveAndAdvance, over: correct) { process in
                With(Subsets(of: sent.union(byzantineVotes))) { inbox in
                    When(received[process].isSubset(of: inbox))
                    received[process].set(inbox)
                    let zeros = inbox.filter { vote in vote.echo == "ECHO0" }.count
                    let ones = inbox.filter { vote in vote.echo == "ECHO1" }.count
                    let reachedQuorum = inbox.mapping { vote in vote.sender }.count >= population - tolerance
                    Either {
                        When(phase[process] == "V0") {
                            sent.insert(Vote.expression(sender: process, echo: "ECHO0"))
                            phase[process].set("S0")
                        }
                        When(phase[process] == "V1") {
                            sent.insert(Vote.expression(sender: process, echo: "ECHO1"))
                            phase[process].set("S1")
                        }
                        When(reachedQuorum && (phase[process] == "S0" || phase[process] == "S1")) {
                            Either {
                                When(zeros >= decideAt) { phase[process].set("D0") }
                                When(ones >= decideAt) { phase[process].set("D1") }
                                When(zeros < decideAt && ones < decideAt) {
                                    Either {
                                        When(zeros >= proposeAt && ones < proposeAt) { phase[process].set("U0") }
                                        When(ones >= proposeAt && zeros < proposeAt) { phase[process].set("U1") }
                                        When(zeros >= proposeAt && ones >= proposeAt) {
                                            phase[process].set(If(phase[process] == "S0", then: "U0", else: "U1"))
                                        }
                                    }
                                }
                            }
                        }
                        When(true) { Skip() }
                    }
                }
            }
            Invariant("TypeOK") {
                sent.isSubset(of: messages)
                Functions(from: correct, to: Set<String>(["V0", "V1", "S0", "S1", "D0", "D1", "U0", "U1"])).contains(phase)
                received.keys == correct && correct.allSatisfy { process in received[process].isSubset(of: messages) }
            }
            let decidedZero = correct.contains { process in phase[process] == "D0" }
            let decidedOne = correct.contains { process in phase[process] == "D1" }
            Invariant("Lemma3_0") { !decidedZero || !decidedOne }
            Invariant("Lemma3_1") { !decidedOne || !decidedZero }
            Invariant("Lemma4_0") { !decidedZero || !correct.contains { process in phase[process] == "U1" } }
            Invariant("Lemma4_1") { !decidedOne || !correct.contains { process in phase[process] == "U0" } }
            Validation("FourProcesses") {
                Bind(population, to: 4)
                Bind(tolerance, to: 1)
                Bind(faultyCount, to: 1)
            }
        }
    }
}
