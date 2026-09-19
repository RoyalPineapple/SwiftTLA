import Testing
import UpstreamParity
@testable import SwiftTLA
@testable import SwiftTLAPlugin

struct PropertyDeclarationNamesTests {
    @Test("refinement binding names supply distinct identities despite equal labels")
    func derivesRefinementNames() throws {
        let first = try labelledRefinements("label: \"Shared label\"").compile()
        let second = try labelledRefinements("label: \"Changed label\"").compile()
        #expect(first.identity == second.identity)
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: first))
        #expect(program.refinements.map(\.name) == ["firstClaim", "secondClaim"])
        #expect(Set(program.refinements.map(\.id)).count == 2)
        #expect(program.refinements.map { program.layout.propertyDisplayName($0.id) } == ["Shared label", "Shared label"])
        let module = try program.renderModule()
        #expect(module.configuration.refinements == ["firstClaim", "secondClaim"])
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

    private func labelledRefinements(_ arguments: String) throws -> TLASpec {
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
            let firstClaim = Refinement(instance: first,
                mappings: [.init(Var<Int>("value"), from: count)], \(arguments))
            firstClaim
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
        for line in [40, 41, 49, 50] {
            #expect(errors.contains {
                $0.contains("InvalidModelProperty.swift:\(line):")
                    && $0.contains("A property label requires one nonempty string literal without interpolation.")
            }, "Missing label diagnostic: \(errors.joined(separator: "\n"))")
        }
    }

    @Test("equal display labels preserve distinct identities, selections, and outcomes")
    func keepsLabelsOutOfSemantics() throws {
        let scenarios = try LabelledPropertyClaims.validationScenarios()
        let all = try NativeScenarioRun(scenarios[0], maximumStates: 4)
        let selected = try NativeScenarioRun(scenarios[1], maximumStates: 4)
        try all.validateExpectations()
        try selected.validateExpectations()
        #expect(all.native.graph == selected.native.graph)
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

    @Test("a label change does not change compilation identity")
    func excludesLabelsFromIdentity() throws {
        func compiled(_ label: String) throws -> CompiledSpecification {
            try SpecParser.parseSpecClosure(named: "LabelIdentity", parseSpecTestClosure("""
            {
                let safe = Invariant(label: "\(label)")
                safe { true }
            }
            """)).compile()
        }
        #expect(try compiled("First label").identity == compiled("Second label").identity)
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
