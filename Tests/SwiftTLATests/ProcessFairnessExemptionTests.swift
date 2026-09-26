import Testing
import Foundation
import SwiftTLAMacros
@testable import SwiftTLA
@testable import SwiftTLAPlugin

struct ProcessFairnessExemptionTests {
    @Test("an exempt entry step permits the same native and compiled stuttering counterexample")
    func exemptEntry() throws {
        let machine = try ProcessFairnessExemptionModel.makeMachine()
        let native = try ReachabilityGraph(initialMachines: [machine], maximumStates: 10)
        #expect(native.transitions.count == 4)
        let result = try #require(native.temporalResults[.Entered])
        #expect(result.status == .violated)
        let witness = try #require(result.witness)
        #expect(witness.cycle == [machine.snapshot, machine.snapshot])
        #expect(witness.cycleActions == [nil])
        #expect(try machine.fairnessConditions().count == 1)

        let compilation = try ProcessFairnessExemptionModel.spec.compile()
        let exploration = try ModelChecker(compilation: compilation,
            configuration: .init(maximumStateLimit: 10, symmetryReduction: .disabled)).explore()
        #expect(exploration.isComplete)
        #expect(try exploration.analyzeTemporalProperties(in: compilation).map(\.status) == [.violated])
        let rendered = try ProcessFairnessExemptionModel.render()
        let fairness = rendered.tlaBundle.tla.split(separator: "\n").filter { $0.contains("WF_") }.joined()
        #expect(fairness.contains("WF_<<entered, pc>>(cs__0)"))
        #expect(!fairness.contains("ncs__0"))
        let plusCal = try rendered.plusCalBundle().root.tla
        #expect(plusCal.contains("fair process"))
        #expect(plusCal.contains("ncs:- while"))
    }

    @Test("weak and strong exemptions retain every transition and only remove the named obligation")
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
            #expect(normal.fairness.count == 2)
            #expect(exempt.fairness.count == 1)
            #expect(normal.fairness.contains(try #require(exempt.fairness.first)))
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
            { Algorithm("InvalidFairness") {
                Each(Set<Int>([0]), fairness: \(policy)) { member in
                    Do(Step.ncs) { Goto(Step.ncs) }
                }
            } }
            """
            let parsed = SpecParser.parseSpecClosure(named: "InvalidFairness", try parseSpecTestClosure(source),
                sourceTypes: .init(enums: [parserTestEnum("Step", cases: ["ncs": .string("ncs")])]))
            #expect(!parsed.diagnostics.isEmpty)
            #expect(throws: SourceParseDiagnostic.self) { _ = try parsed.compile() }
        }
    }
}
