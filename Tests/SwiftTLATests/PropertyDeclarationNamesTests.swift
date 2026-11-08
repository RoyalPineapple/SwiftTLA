import Testing
import UpstreamParity
@testable import SwiftTLA
@testable import SwiftTLAPlugin

struct PropertyDeclarationNamesTests {
    @Test("unbound property handles explain binding and registration")
    func rejectsAnonymousPropertyHandle() throws {
        for source in [
            "{ Invariant() }",
            "{ Reachable() }",
            "{ let counter = Algorithm { Eventually() }; counter }"
        ] {
            let spec = SpecParser.parseSpecClosure(named: "AnonymousProperty", try parseSpecTestClosure(source))
            let diagnostic = try #require(spec.diagnostics.first)
            #expect(diagnostic.message.contains("Bind the property handle to an immutable let"))
            #expect(diagnostic.sourceSpan.location != .unavailable)
            #expect(throws: SourceParseDiagnostic.self) { try spec.compile() }
        }
    }

    @Test("refinement binding names supply distinct identities despite equal labels",
        arguments: ["firstClaim", "Len", "Spec", "WF_claim", "SF_claim", "_1"])
    func derivesRefinementNames(name: String) throws {
        let first = try labelledRefinements("label: \"Shared label\"", firstName: name).compile()
        let second = try labelledRefinements("label: \"Changed label\"", firstName: name).compile()
        #expect(first.identity == second.identity)
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: first))
        #expect(program.layout.refinementProperties.map(\.declaration.name) == [name, "secondClaim"])
        #expect(program.refinements.map(\.name).allSatisfy { !["Len", "Spec"].contains($0) })
        if let expected = ["WF_claim": "_WF_claim", "SF_claim": "_SF_claim", "_1": "v_1"][name] {
            #expect(program.refinements.first?.name == expected)
        }
        #expect(Set(program.refinements.map(\.id)).count == 2)
        #expect(program.refinements.map { program.layout.propertyDisplayName($0.id) } == ["Shared label", "Shared label"])
        let module = try program.renderModule()
        #expect(module.configuration.refinements == program.refinements.map(\.name))
        #expect(!module.renderedModuleSource.contains("Shared label"))
    }

    @Test("invalid refinement display labels fail at their declaration", arguments: [
        "label: 1", "label: \"\"", "label: \"text \\(1)\"", "label: \"one\", label: \"two\""
    ])
    func rejectsInvalidRefinementLabels(arguments: String) throws {
        let spec = try labelledRefinements(arguments)
        #expect(spec.diagnostics.contains { $0.message == "A property label requires one nonempty string literal without interpolation." })
        #expect(throws: (any Error).self) { try spec.compile() }
    }

    private func labelledRefinements(_ arguments: String, firstName: String = "firstClaim") throws -> TLASpec {
        SpecParser.parseSpecClosure(named: "RefinementLabels", try parseSpecTestClosure("""
        {
            let abstract = TLASpec("Abstract") {
                let value = Var<Int>("value")
                Variable(value, 0)
                SwiftTLA.Action("stay") { value.stays }
            }
            let count = Var<Int>("count")
            Variable(count, 0)
            SwiftTLA.Action("stay") { count.stays }
            let first = Instance("First", of: abstract)
            first
            let second = Instance("Second", of: abstract)
            second
            let \(firstName) = Refinement(instance: first,
                mappings: [.init(Var<Int>("value"), from: count)], \(arguments))
            \(firstName)
            let secondClaim = Refinement(instance: second,
                mappings: [.init(Var<Int>("value"), from: count)], label: "Shared label")
            secondClaim
        }
        """))
    }

    @Test("standalone spec macros reject invalid labels during Swift compilation")
    func rejectsInvalidSwiftLabels() throws {
        let build = try buildExternalConsumer("InvalidModelProperty")
        #expect(build.status != 0)
        let errors = build.output.split(separator: "\n").filter { $0.contains(": error:") }
        for line in [42, 43, 51, 52] {
            #expect(errors.contains {
                $0.contains("InvalidModelProperty.swift:\(line):")
                    && $0.contains("A property label requires one nonempty string literal without interpolation.")
            }, "Missing label diagnostic: \(errors.joined(separator: "\n"))")
        }
    }

    @Test("equal display labels preserve distinct identities, selections, and outcomes")
    func keepsLabelsOutOfSemantics() throws {
        let scenarios = try LabelledPropertyClaims.validationScenarios()
        #expect(scenarios.map(\.name) == ["All", "Selected"])
        #expect(scenarios.map(\.displayName) == ["Shared scenario", "Shared scenario"])
        let all = try NativeScenarioRun(scenarios[0], maximumStates: 4)
        let selected = try NativeScenarioRun(scenarios[1], maximumStates: 4)
        try all.validateExpectations()
        try selected.validateExpectations()
        #expect(all.native.graph == nil)
        let selectedGraph = try #require(selected.native.graph)
        #expect(selectedGraph.isComparable)
        guard case .violated(let violation)? = all.native.checks.properties["safe"],
              case .reached(let reachability)? = selected.native.checks.properties["reachable"] else {
            Issue.record("Equal labels must preserve the distinct invariant and reachability outcomes")
            return
        }
        #expect(violation.steps.count == 1)
        #expect(violation.steps == reachability.steps)
        #expect(Set(violation.steps.map(\.state)) == selectedGraph.graph.initialStateKeys)
        #expect(all.native.checks.properties["always"] == .unavailable)
        #expect(selected.native.checks.properties["always"] == .satisfied)
        #expect(Set(selected.native.checks.properties.keys) == ["reachable", "always"])
        #expect(LabelledPropertyClaims.formalPropertyNames.count == 7)
        #expect(Set(LabelledPropertyClaims.formalPropertyNames.values).count == 7)
        #expect(Set(LabelledPropertyClaims.propertyDisplayNames.values) == ["Safety / progress"])
        #expect(all.coverage.propertyDisplayNames.count == 7)
        #expect(scenarios[1].checking.properties == [.reachable, .always])
        let rendered = try scenarios[0].render()
        #expect(!rendered.tlaBundle.tla.contains("Safety / progress"))
        #expect(try rendered.plusCalBundle().root.cfg == rendered.tlaBundle.root.cfg)
        #expect(QualifiedPropertyClaims.propertyDisplayNames == QualifiedPropertyClaims.formalPropertyNames)
    }

    @Test("invalid display labels fail at their declaration", arguments: [
        "label: 1", "label: \"\"", "label: \"text \\(1)\"", "label: \"one\", label: \"two\""
    ])
    func rejectsInvalidLabels(arguments: String) throws {
        let spec = SpecParser.parseSpecClosure(named: "InvalidLabel", try parseSpecTestClosure("""
        {
            let safe = Invariant(\(arguments))
            safe { true }
        }
        """))
        #expect(throws: (any Error).self) { try spec.compile() }
    }

    @Test("property binding names preserve selections independently of labels",
        arguments: ["safe", "Len", "Spec"], ["Invariant", "Reachable", "Always"])
    func excludesLabelsFromIdentity(name: String, kind: String) throws {
        func compiled(_ label: String) throws -> CompiledSpecification {
            try SpecParser.parseSpecClosure(named: "LabelIdentity", parseSpecTestClosure("""
            { scope in
                let count = scope.sharedVar(initial: 0)
                let \(name) = \(kind)(label: "\(label)")
                \(kind == "Always" ? "\(name)(count == 0)" : "\(name) { count == 0 }")
            }
            """)).compile()
        }
        let first = try compiled("First label")
        #expect(first.identity == (try compiled("Second label")).identity)
        let runtime = CompiledRuntime(compilation: first)
        let initial = try #require(try runtime.initialStates().first)
        let queries = (first.semantics.behavior.invariants + first.semantics.behavior.reachabilityProperties).map(\.predicate)
            + first.semantics.behavior.temporalProperties.flatMap { $0.expression.predicates }
        #expect(queries.count == 1)
        #expect(try runtime.predicateHolds(try #require(queries.first), in: initial))
        #expect(first.layout.properties.map(\.declaration.name) == [name])
        #expect(first.layout.propertyDisplayName(try #require(first.layout.properties.first).id) == "First label")
        #expect(first.description.invariants + first.description.reachabilityProperties + first.description.temporalProperties == [name])
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: first))
        let module = try program.renderModule()
        let selected = module.configuration.invariants + module.configuration.reachabilityProperties + module.configuration.properties
        #expect(selected.count == 1)
        let formalName = try #require(selected.first)
        #expect(!["Len", "Spec"].contains(formalName))
        #expect(module.renderedModuleSource.contains("\(formalName) =="))
        let emitter = NativeSwiftEmitter(model: try MacroCompilation(typeName: "LabelIdentity", program: program))
        let nativeNames = try emitter.propertyIdentityDeclarations().map(\.description).joined(separator: "\n")
        #expect(nativeNames.contains(".\(name): \"\(formalName)\""))
        #expect(module.renderedModuleSource.split(separator: "\n").filter { $0.hasPrefix("Spec ==") }.count == 1)
    }

    @Test("qualified property constructors share Swift names across built and generated models")
    func preservesQualifiedBindingNames() throws {
        let scenario = try #require(try QualifiedPropertyClaims.validationScenarios().first)
        #expect(scenario.checking.properties == [.safe, .reachable, .always, .eventually, .recurring, .stable, .response])
        let run = try NativeScenarioRun(scenario, maximumStates: 4)
        try run.validateExpectations()
        let rendered = try scenario.render()
        let cfg = try #require(rendered.tlaBundle.root.cfg)
        #expect(cfg.contains("INVARIANT safe"))
        #expect(cfg.contains("PROPERTY response"))
        #expect(try rendered.plusCalBundle().root.cfg == cfg)
        #expect(try QualifiedPropertyClaims.spec.compile().identity == QualifiedPropertyClaims.spec.compile().identity)
    }
}
