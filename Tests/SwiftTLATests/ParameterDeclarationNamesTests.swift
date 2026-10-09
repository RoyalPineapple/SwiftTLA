import SwiftTLA
import Testing
@testable import SwiftTLAPlugin

@Suite struct ParameterDeclarationNamesTests {
    @Test("parameter labels appear in typed configuration and compilation reports")
    func exposesParameterDisplayNames() throws {
        let compiled = try LabeledParametersModel.spec.compile()
        #expect(compiled.description.parameters.map(\.name) == ["limit", "enabled"])
        #expect(compiled.description.parameters.map(\.displayName) == ["Visit limit", "enabled"])
        #expect(LabeledParametersModel.Configuration.displayNames[\LabeledParametersModel.Configuration.limit] == "Visit limit")
        #expect(LabeledParametersModel.Configuration.displayNames[\LabeledParametersModel.Configuration.enabled] == "enabled")

        let scenario = try #require(LabeledParametersModel.validationScenarios().first)
        let machine = try #require(scenario.initialMachines().first)
        #expect(machine.configuration.limit == 1)
        #expect(try !scenario.render().tlaBundle.tla.contains("Visit limit"))
    }

    @Test("changing a parameter label preserves compiled identity")
    func labelIsPresentationOnly() throws {
        func compile(_ label: String) throws -> CompiledSpecification {
            try SpecParser.parseSpecClosure(named: "ParameterIdentity", parseSpecTestClosure("""
            { scope in let limit = scope.parameter(as: Int.self, in: 0...2, label: "\(label)") }
            """)).compile()
        }
        let first = try compile("Visit limit")
        let second = try compile("Maximum visits")
        #expect(first.identity == second.identity)
        #expect(first.description.parameters.first?.name == second.description.parameters.first?.name)
        #expect(first.description.parameters.first?.displayName == "Visit limit")
        #expect(second.description.parameters.first?.displayName == "Maximum visits")
    }

    @Test("equal parameter labels preserve distinct declarations")
    func duplicateParameterLabelsRemainDistinct() throws {
        let spec = SpecParser.parseSpecClosure(named: "ParameterLabels", try parseSpecTestClosure("""
        { scope in
            let first = scope.parameter(as: Bool.self, label: "Shared label")
            let second = scope.parameter(as: Bool.self, label: "Shared label")
        }
        """))
        let parameters = try spec.compile().description.parameters
        #expect(parameters.map(\.name) == ["first", "second"])
        #expect(parameters.map(\.displayName) == ["Shared label", "Shared label"])
    }

    @Test("parameter labels require one nonempty literal at the declaration")
    func rejectsInvalidParameterLabels() throws {
        for argument in ["1", "\"\"", "\"limit \\(1)\"", "\"one\", label: \"two\""] {
            let spec = SpecParser.parseSpecClosure(named: "InvalidParameterLabel", try parseSpecTestClosure("""
            { scope in let limit = scope.parameter(as: Int.self, in: 0...2, label: \(argument)) }
            """))
            let diagnostic = try #require(spec.diagnostics.first)
            #expect(diagnostic.message == "A parameter label requires one nonempty string literal without interpolation.")
            #expect(diagnostic.sourceSpan.location != .unavailable)
            #expect(throws: SourceParseDiagnostic.self) { try spec.compile() }
        }
    }

    @Test("invalid parameter labels fail in an external Swift consumer")
    func rejectsInvalidSwiftParameterLabel() throws {
        let build = try buildExternalConsumer("InvalidParameterDisplayLabel")
        #expect(build.status != 0)
        let diagnostics = build.output.split(separator: "\n").filter {
            $0.contains("A parameter label requires one nonempty string literal without interpolation.")
        }
        #expect(!diagnostics.isEmpty, "Expected a parameter-label diagnostic: \(build.output)")
        #expect(build.output.contains("InvalidParameterDisplayLabel.swift:9:"))
    }
}
