import Testing
import SwiftTLA

@Suite("Generated refinement behavior")
struct GeneratedRefinementBehaviorTests {
    @Test("safety refinement frames cover the complete abstract declaration")
    func retainsCompleteAbstractFrame() throws {
        let source = try StutteringRefinementSource.render()
        let mapped = try source.addingGeneratedRefinement("SequenceSafety", instance: "sequences",
            of: ConfiguredSequenceDomainMachine.self,
            configuration: .init(members: Set<Int>([]), lengths: Set<Int>([0])),
            behavior: .initialAndNext,
            parameters: [(\ConfiguredSequenceDomainMachine.Configuration.members, "{}"),
                         (\ConfiguredSequenceDomainMachine.Configuration.lengths, "{0}")],
            state: [(\ConfiguredSequenceDomainMachine.State.zeroBased, "[k \\in {} |-> 0]"),
                    (\ConfiguredSequenceDomainMachine.State.sorted, "<<>>"),
                    (\ConfiguredSequenceDomainMachine.State.row, "<<>>")])
        #expect(mapped.tlaBundle.root.tla.contains(
            "SequenceSafety == sequences!Init /\\ [][sequences!Next]_<<(<<>>), (<<>>), ([k \\in {} |-> 0])>>"))

        let hidden = try source.addingGeneratedRefinement("HiddenSafety", instance: "hidden",
            of: ConfiguredAlgorithmBindingMachine.self, configuration: .init(limit: 1),
            behavior: .initialAndNext,
            parameters: [(\ConfiguredAlgorithmBindingMachine.Configuration.limit, "1")],
            state: [(\ConfiguredAlgorithmBindingMachine.State.row, "<<>>")])
        let target = try #require(hidden.tlaBundle.imports.first { $0.name == "ConfiguredAlgorithmBindingMachine" })
        try #require(target.tla.contains("vars == <<pc, row>>\n"), "The guard case must include hidden control state")
        #expect(hidden.tlaBundle.root.tla.contains(
            "HiddenSafety == hidden!Init /\\ [][hidden!Next]_hidden!vars"))
    }

    @Test("generated refinement maps non-initial states and respects selected abstract fairness")
    func explicitSafetyOnlyRefinement() throws {
        let initial = try StutteringRefinementSource.initialMachines()
        var graph = try ReachabilityGraph(initialMachines: initial, maximumStates: 10)
        let machine = try #require(initial.first)
        let failures = try machine.refinementFailures(in: &graph)
        #expect(failures[.Safety] == nil)
        guard case .fairness? = failures[.Full] else {
            Issue.record("Full abstract behavior should reject perpetual stuttering")
            return
        }

        let rendered = try StutteringRefinementSource.render()
        #expect(rendered.tlaBundle.root.tla.contains("Full == abstract!Spec"))
        #expect(rendered.tlaBundle.root.tla.contains(
            "Safety == abstract!Init /\\ [][abstract!Next]_(value)"))
        let instances = rendered.tlaBundle.root.tla.split(separator: "\n").filter {
            $0.hasPrefix("abstract == INSTANCE ")
        }
        #expect(instances.count == 1)

        let shifted = try rendered.addingGeneratedRefinement("ShiftedSafety", instance: "abstract",
            of: FairRefinementTarget.self, configuration: .init(N: 1), behavior: .initialAndNext,
            parameters: [(\FairRefinementTarget.Configuration.N, "1")],
            state: [(\FairRefinementTarget.State.value, "(value + 1)")])
        let shiftedInstances = shifted.tlaBundle.root.tla.split(separator: "\n").filter {
            $0.contains(" == INSTANCE FairRefinementTarget ")
        }
        #expect(shiftedInstances.count == 2)
        #expect(Set(shiftedInstances.map { $0.components(separatedBy: " == ")[0] }).count == 2)
        #expect(shifted.tlaBundle.root.tla.contains("Safety == abstract!Init /\\ [][abstract!Next]_(value)"))
        #expect(shifted.tlaBundle.root.tla.contains("_((value + 1))"))

        let repeated = try shifted.addingGeneratedRefinement("RepeatedSafety", instance: "abstract",
            of: FairRefinementTarget.self, configuration: .init(N: 1), behavior: .initialAndNext,
            parameters: [(\FairRefinementTarget.Configuration.N, "1")],
            state: [(\FairRefinementTarget.State.value, "(value + 1)")])
        #expect(repeated.tlaBundle.root.tla.split(separator: "\n").filter {
            $0.contains(" == INSTANCE FairRefinementTarget ")
        } == shiftedInstances)
        if case .compiled(_, let ownership, let dependencies) = repeated.tlaBundle.provenance {
            #expect(ownership.filter { $0.structuralPath == ["abstract"] }.count == 1)
            #expect(ownership.filter { $0.structuralPath == ["abstract_"] }.count == 1)
            #expect(dependencies.filter { $0.structuralPath == ["abstract"] }.count == 1)
            #expect(dependencies.filter { $0.structuralPath == ["abstract_"] }.count == 1)
        } else {
            Issue.record("Generated refinement exports must retain compiled provenance")
        }
    }
}
