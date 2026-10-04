import Testing
import Foundation
import SwiftTLAMacros
@testable import SwiftTLA
@testable import SwiftTLAPlugin

struct ProcessFairnessExemptionTests {
    @Test("process fairness is one obligation over all eligible atomic steps")
    func groupedProcessFairness() throws {
        let machine = try ProcessFairnessGroupModel.makeMachine()
        let conditions = try machine.fairnessConditions()
        #expect(conditions.count == 1)
        let first = try #require(machine.successors().first)
        let second = try #require(first.machine.successors().first)
        #expect(conditions[0].matches(first.action))
        #expect(conditions[0].matches(second.action))
        let rendered = try ProcessFairnessGroupModel.render()
        let obligations = rendered.tlaBundle.root.tla.split(separator: "\n").filter { $0.contains("WF_") }
        #expect(obligations.count == 1)
        #expect(obligations[0].contains("first"))
        #expect(obligations[0].contains("second"))
        #expect(obligations[0].contains("\\/"))
    }

    @Test("an exempt entry step permits a generated-machine stuttering counterexample")
    func exemptEntry() throws {
        let machine = try ProcessFairnessExemptionModel.makeMachine()
        let native = try MachineValidationGraph(initialMachines: [machine], maximumStates: 10)
        #expect(native.transitions.count == 4)
        let result = try #require(native.temporalResults(checking: [.Entered])[.Entered])
        #expect(result.status == .violated)
        let witness = try #require(result.witness)
        #expect(witness.cycle == [machine.snapshot, machine.snapshot])
        #expect(witness.cycleActions == [nil])
        #expect(try machine.fairnessConditions().count == 1)
        let rendered = try ProcessFairnessExemptionModel.render()
        let fairness = rendered.tlaBundle.tla.split(separator: "\n").filter { $0.contains("WF_") }.joined()
        #expect(fairness.contains("WF_<<entered, pc>>"))
        #expect(fairness.contains("cs(_process)"))
        #expect(!fairness.contains("ncs__0"))
        let plusCal = try rendered.plusCalBundle().root.tla
        #expect(plusCal.contains("fair process"))
        #expect(plusCal.contains("ncs:- while"))
    }

    @Test("weak and strong exemptions retain transitions and narrow the process obligation")
    func policyAndTransitions() throws {
        typealias Step = ProcessFairnessExemptionModel.Step
        let policies: [(ProcessFairness, ProcessFairness, ProcessFairness)] = [
            (.weak, .weak(excluding: [Step.ncs]), .weak(excluding: [Step]())),
            (.strong, .strong(excluding: [Step.ncs]), .strong(excluding: [Step]()))
        ]
        for (inherited, excluded, empty) in policies {
            func specification(_ policy: ProcessFairness) -> TLASpec {
                TLASpec("FairnessPolicies") {
                    Algorithm("FairnessPolicies") {
                        Each(SetExpr<Int>.literal(0), fairness: policy) { _ in
                            Do(Step.ncs) { Goto(Step.cs) }
                            Do(Step.cs) { Goto(Step.ncs) }
                        }
                    }
                }
            }
            let normal = try specification(inherited).loweredSourceModel()
            let exempt = try specification(excluded).loweredSourceModel()
            #expect(try specification(empty).loweredSourceModel().fairness == normal.fairness)
            #expect(normal.actions.map(\.body) == exempt.actions.map(\.body))
            #expect(normal.variables.map(\.initialization) == exempt.variables.map(\.initialization))
            #expect(normal.fairness.count == 1)
            #expect(exempt.fairness.count == 1)
            #expect(try #require(normal.fairness.first).description.contains("ncs \\/ cs"))
            #expect(try #require(exempt.fairness.first).description.contains("cs"))
            #expect(!exempt.fairness[0].description.contains("ncs"))
            let plusCal = try specification(excluded).compile().render().plusCalBundle().root.tla
            #expect(plusCal.contains("ncs:-"))
            #expect(!plusCal.split(separator: "\n").contains {
                $0.trimmingCharacters(in: .whitespaces).hasPrefix("cs:-")
            })
        }
    }

    @Test("duplicate and unknown exemptions fail instead of silently changing fairness")
    func invalidExemptions() {
        typealias Step = ProcessFairnessExemptionModel.Step
        for (labels, expected) in [([Step.ncs, .ncs], AlgorithmDiagnosticCode.duplicateFairnessExemption),
                                   ([Step.missing], .invalidFairnessExemption)] {
            let algorithm = Algorithm("InvalidFairnessExemption") {
                Each(Set<Int>([0]), fairness: .weak(excluding: labels)) { _ in
                    Do(Step.ncs) { Goto(Step.ncs) }
                }
            }
            #expect(algorithm.validate().map(\.code) == [expected])
        }
    }

    @Test("macro parsing rejects malformed fairness factories and untyped labels")
    func invalidSyntax() throws {
        for policy in [".none(excluding: [Step.ncs])", ".weak(excluding: [\"ncs\"])",
                       ".weak([Step.ncs])", ".weak(excluding: [Step.ncs], extra: true)"] {
            let source = """
            {
                let invalidFairness = Algorithm(label: "InvalidFairness") {
                    Each(Set<Int>([0]), fairness: \(policy)) { member in
                        Do(Step.ncs) { Goto(Step.ncs) }
                    }
                }
                invalidFairness
            }
            """
            let parsed = SpecParser.parseSpecClosure(named: "InvalidFairness", try parseSpecTestClosure(source),
                sourceTypes: .init(enums: [parserTestEnum("Step", cases: ["ncs": .string("ncs")])]))
            #expect(!parsed.diagnostics.isEmpty)
            #expect(throws: SourceParseDiagnostic.self) { _ = try parsed.compile() }
        }
    }
}
