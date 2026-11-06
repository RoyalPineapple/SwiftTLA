import Testing
import SwiftTLA
import UpstreamParity

@Suite("Generated refinement behavior")
struct GeneratedRefinementBehaviorTests {
    @Test("generated refinement imports bind the target's closed finite constants")
    func retainsAbstractFiniteConstants() throws {
        let configuration = try FairRefinementTarget.Configuration(N: 1)
        let initial = try #require(try FairRefinementTarget.initialMachines(configuration: configuration).first)
        #expect(initial.state.value == 0)
        let target = try FairRefinementTarget.render(configuration: configuration)
        let concreteField = try #require(ConfiguredCounter.State.fieldIdentities[\ConfiguredCounter.State.value]?.formalName)
        let constants = [("EnabledValue", "TRUE", "EnabledValue"), ("FiniteValues", "{1, 2}", "FiniteValues"),
                         ("TextValue", #""left = right""#, "TextValue")]
        for (name, value, _) in constants {
            try #require(target.tlaBundle.cfg.contains("CONSTANT \(name) = \(value)\n"))
        }
        func importing(_ source: RenderedSpecification, name: String) throws -> RenderedSpecification {
            try source.addingGeneratedRefinement(name, instance: "finite", of: FairRefinementTarget.self,
                configuration: configuration, behavior: .initialAndNext,
                parameters: [(\FairRefinementTarget.Configuration.N, "1")],
                state: [(\FairRefinementTarget.State.value, concreteField)])
        }
        let rendered = try importing(
            ConfiguredCounter.render(configuration: .init(limit: 1, stopAtLimit: true)), name: "FiniteSafety")
        let repeated = try importing(rendered, name: "FiniteSafetyAgain")
        let authored = try rendered.plusCalBundle()
        for (name, value, symbol) in constants {
            for bundle in [rendered.tlaBundle, authored] {
                #expect(bundle.tla.contains("\(name) <- (\(symbol))"))
                #expect(bundle.cfg.contains("CONSTANT \(symbol) = \(value)\n"))
            }
            #expect(repeated.tlaBundle.cfg.split(separator: "\n").filter {
                $0 == "CONSTANT \(symbol) = \(value)"
            }.count == 1)
        }
        for (name, value) in [("Minimum", "-1"), ("QuotedText", #""a\"b""#)] {
            for bundle in [target.tlaBundle, rendered.tlaBundle, authored, repeated.tlaBundle] {
                let binding = try #require(bundle.cfg.split(separator: "\n").first {
                    $0.hasPrefix("CONSTANT \(name) <- ")
                })
                let definition = binding.dropFirst("CONSTANT \(name) <- ".count)
                #expect(bundle.root.tla.contains("\(definition) == \(value)\n"))
                #expect(!bundle.cfg.contains("CONSTANT \(name) ="))
            }
            #expect(rendered.tlaBundle.root.tla.contains("\(name) <- (\(name))"))
            #expect(repeated.tlaBundle.cfg.split(separator: "\n").filter {
                $0.hasPrefix("CONSTANT \(name) <- ")
            }.count == 1)
        }
        #expect(repeated.tlaBundle.tla.split(separator: "\n").filter {
            $0.hasPrefix("finite == INSTANCE ")
        }.count == 1)
    }

    @Test("generated refinement imports retain abstract model values in the root module and configuration")
    func retainsAbstractModelValues() throws {
        let configuration = try ArrayValueMachine.Configuration(input: [])
        let initial = try #require(try ArrayValueMachine.initialMachines(configuration: configuration).first)
        #expect(initial.state.row.isEmpty)
        #expect(initial.state.choices == [.one, .two, .one])
        let target = try ArrayValueMachine.render(configuration: configuration)
        try #require(target.tlaBundle.cfg.contains("CONSTANT one = one\n"))
        try #require(target.tlaBundle.cfg.contains("CONSTANT two = two\n"))

        func importingValues(_ source: RenderedSpecification, name: String) throws -> RenderedSpecification {
            try source.addingGeneratedRefinement(name, instance: "collection", of: ArrayValueMachine.self,
                configuration: configuration, behavior: .initialAndNext,
                parameters: [(\ArrayValueMachine.Configuration.input, "<<>>")],
                state: [(\ArrayValueMachine.State.row, "<<>>"),
                        (\ArrayValueMachine.State.choices, "<<>>")])
        }
        let rendered = try importingValues(StutteringRefinementSource.render(configuration: .init(flag: true)), name: "CollectionSafety")
        #expect(rendered.tlaBundle.root.tla.contains("CONSTANTS one, two\n"))
        #expect(rendered.tlaBundle.root.tla.contains("one <- (one)"))
        #expect(rendered.tlaBundle.root.tla.contains("two <- (two)"))
        #expect(rendered.tlaBundle.cfg.contains("CONSTANT one = one\n"))
        #expect(rendered.tlaBundle.cfg.contains("CONSTANT two = two\n"))

        let differentlyConfigured = try rendered.addingGeneratedRefinement(
            "RepeatedInputSafety", instance: "collection", of: ArrayValueMachine.self,
            configuration: .init(input: [2, 1, 2]), behavior: .initialAndNext,
            parameters: [(\ArrayValueMachine.Configuration.input, "<<2, 1, 2>>")],
            state: [(\ArrayValueMachine.State.row, "<<>>"),
                    (\ArrayValueMachine.State.choices, "<<>>")])
        #expect(differentlyConfigured.tlaBundle.imports.filter { $0.name == "ArrayValueMachine" }.count == 1)
        #expect(differentlyConfigured.tlaBundle.root.tla.contains("input <- (<<2, 1, 2>>)"))
        #expect(!differentlyConfigured.tlaBundle.imports.contains {
            $0.tla.contains("__SwiftTLAParameter")
        })

        let repeated = try importingValues(rendered, name: "CollectionSafetyAgain")
        #expect(repeated.tlaBundle.root.tla.split(separator: "\n").filter {
            $0.hasPrefix("collection == INSTANCE ")
        }.count == 1)
        for name in ["one", "two"] {
            #expect(repeated.tlaBundle.cfg.split(separator: "\n").filter {
                $0 == "CONSTANT \(name) = \(name)"
            }.count == 1)
        }

        let occupied = try StutteringRefinementSource.render(configuration: .init(flag: true)).addingGeneratedRefinement(
            "OneSafety", instance: "one", of: FairRefinementTarget.self,
            configuration: .init(N: 1), behavior: .initialAndNext,
            parameters: [(\FairRefinementTarget.Configuration.N, "1")],
            state: [(\FairRefinementTarget.State.value, "value")])
        try #require(occupied.tlaBundle.root.tla.contains("one == INSTANCE FairRefinementTarget "))
        let collision = try importingValues(occupied, name: "CollisionSafety")
        #expect(collision.tlaBundle.root.tla.contains("CONSTANTS one_, two\n"))
        #expect(collision.tlaBundle.root.tla.contains("one <- (one_)"))
        #expect(collision.tlaBundle.cfg.contains("CONSTANT one_ = one\n"))
        #expect(collision.tlaBundle.root.tla.contains("one == INSTANCE FairRefinementTarget "))
        let repeatedCollision = try importingValues(collision, name: "CollisionSafetyAgain")
        #expect(repeatedCollision.tlaBundle.cfg.split(separator: "\n").filter {
            $0 == "CONSTANT one_ = one"
        }.count == 1)
        #expect(repeatedCollision.tlaBundle.root.tla.split(separator: "\n").filter {
            $0.hasPrefix("collection == INSTANCE ")
        }.count == 1)

        let configured = try importingValues(
            ConfiguredCounter.render(configuration: .init(limit: 1, stopAtLimit: true)),
            name: "ConfiguredCollectionSafety")
        let authored = try configured.plusCalBundle()
        #expect(authored.cfg == configured.tlaBundle.cfg)
        #expect(authored.provenance == configured.tlaBundle.provenance)
        for bundle in [configured.tlaBundle, authored] {
            #expect(bundle.tla.contains("CONSTANTS one_, two\n"))
            #expect(bundle.tla.contains("one <- (one_)"))
            #expect(bundle.cfg.contains("CONSTANT one_ = one\n"))
            #expect(!bundle.cfg.contains("CONSTANT input"))
            #expect(!bundle.cfg.contains("INVARIANT Shape\n"))
        }
    }

    @Test("safety refinement frames cover the complete abstract declaration")
    func retainsCompleteAbstractFrame() throws {
        let source = try StutteringRefinementSource.render(configuration: .init(flag: true))
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
        let initial = try StutteringRefinementSource.initialMachines(configuration: .init(flag: true))
        var graph = try ReachabilityGraph(initialMachines: initial, maximumStates: 10)
        let machine = try #require(initial.first)
        let failures = try machine.refinementFailures(in: &graph)
        #expect(failures[.Safety] == nil)
        guard case .fairness? = failures[.Full] else {
            Issue.record("Full abstract behavior should reject perpetual stuttering")
            return
        }

        let rendered = try StutteringRefinementSource.render(configuration: .init(flag: true))
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

        let alternate = try StutteringRefinementSource.render(configuration: .init(flag: false))
        let alternateInitial = try #require(try StutteringRefinementSource.initialMachines(
            configuration: .init(flag: false)).first)
        #expect(alternateInitial.state.value == 0)
        var alternateGraph = try ReachabilityGraph(initialMachines: [alternateInitial], maximumStates: 10)
        let alternateFailures = try alternateInitial.refinementFailures(in: &alternateGraph)
        #expect(alternateGraph.transitions.count == graph.transitions.count)
        #expect(alternateFailures[.Safety] == nil)
        guard case .fairness? = alternateFailures[.Full] else {
            Issue.record("The alternate configuration must retain the full-behavior fairness failure")
            return
        }
        #expect(rendered.tlaBundle.cfg.contains("CONSTANT flag = TRUE\n"))
        #expect(alternate.tlaBundle.cfg.contains("CONSTANT flag = FALSE\n"))
        #expect(rendered.tlaBundle.root.tla == alternate.tlaBundle.root.tla)
        let concreteField = try #require(ConfiguredCounter.State.fieldIdentities[\ConfiguredCounter.State.value]?.formalName)
        let source = try ConfiguredCounter.render(configuration: .init(limit: 1, stopAtLimit: true))
        let nested = try source.addingGeneratedRefinement("NestedSafety", instance: "nested",
            of: StutteringRefinementSource.self, configuration: .init(flag: true), behavior: .initialAndNext,
            parameters: [(\StutteringRefinementSource.Configuration.flag, "TRUE")],
            state: [(\StutteringRefinementSource.State.value, concreteField)])
        let nestedAgain = try nested.addingGeneratedRefinement("AlternateNestedSafety", instance: "nested",
            of: StutteringRefinementSource.self, configuration: .init(flag: false), behavior: .initialAndNext,
            parameters: [(\StutteringRefinementSource.Configuration.flag, "FALSE")],
            state: [(\StutteringRefinementSource.State.value, concreteField)])
        #expect(nestedAgain.tlaBundle.imports.filter { $0.name == "StutteringRefinementSource" }.count == 1)
        #expect(nestedAgain.tlaBundle.root.tla.contains("flag <- (TRUE)"))
        #expect(nestedAgain.tlaBundle.root.tla.contains("flag <- (FALSE)"))

        let collision = try source.addingGeneratedRefinement("__SwiftTLAParameter0_",
            instance: "__SwiftTLAParameter0", of: FairRefinementTarget.self,
            configuration: .init(N: 1), behavior: .initialAndNext,
            parameters: [(\FairRefinementTarget.Configuration.N, "1")],
            state: [(\FairRefinementTarget.State.value, concreteField)])
        for bundle in [collision.tlaBundle, try collision.plusCalBundle()] {
            #expect(bundle.root.tla.contains("__SwiftTLAParameter0__ == INSTANCE FairRefinementTarget "))
            #expect(bundle.root.tla.contains("__SwiftTLAParameter0_ == __SwiftTLAParameter0__!Init"))
        }
    }
}
