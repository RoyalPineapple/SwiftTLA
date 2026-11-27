@testable import SwiftTLA
import Testing
@testable import SwiftTLAPlugin

@Suite struct ParameterDeclarationNamesTests {
    @Test("exact upstream names survive configuration, execution and formal export")
    func exactNamesAcrossGeneratedMachine() throws {
        let configuration = try UpstreamDeclarationNames.Configuration(writers: [1, 2])
        let scenario = try #require(UpstreamDeclarationNames.validationScenarios().first)
        #expect(scenario.configuration == configuration)
        var machine = try UpstreamDeclarationNames.makeMachine(configuration: configuration)
        #expect(machine.configuration.writers == [1, 2])
        #expect(machine.state.published == -1)
        try machine.send(.publish)
        #expect(machine.state.published == 0)
        #expect(machine.state.nextSequence == 1)
        let projection = try machine.formalProjection(of: machine.snapshot)
        let sequence = try #require(TLAStateProjection.Token(validating: "next_sequence"))
        #expect(projection.value(for: sequence) == .int(1))
        let graph = try scenario.explore(maximumStates: 4)
        let violation = try #require(graph.safetyViolations.first { $0.value.contains(.invariant(.Unpublished)) })
        let trace = try graph.trace(to: violation.key)
        #expect(trace.compactMap(\.action) == [.publish])
        #expect(try trace.map { try machine.formalProjection(of: $0.state).value(for: sequence) } == [.int(0), .int(1)])
        let generated = try scenario.render().tlaBundle
        #expect(generated.tla.contains("CONSTANTS Writers"))
        #expect(generated.tla.contains("next_sequence'"))
        #expect(generated.cfg.contains("CONSTANT Writers = {1, 2}"))
        let runtime = try UpstreamDeclarationNames.spec.compile()
        #expect(runtime.layout.variables.map(\.formalName) == ["published", "next_sequence"])
        let parameter = try #require(runtime.layout.parameters.first)
        #expect(runtime.bindings.binders[parameter.binder] == "Writers")
    }

    @Test("an exact request identifies its Swift declaration when allocation cannot honor it",
          arguments: ["published", "Writers", "IF", "Init", "vars", "Bad-Name", ""])
    func rejectsUnavailableExactNames(_ requested: String) throws {
        let spec = SpecParser.parseSpecClosure(named: "UnavailableName", try parseSpecTestClosure("""
            { scope in
                let writers = scope.parameter(tlaName: "Writers", as: Bool.self)
                let published = scope.sharedVar(initial: -1)
                let nextSequence = scope.sharedVar(tlaName: "\(requested)", initial: 0)
            }
            """))
        do {
            _ = try spec.compile()
            Issue.record("Accepted unavailable name '\(requested)'")
        } catch let error as CompilationDiagnostic {
            #expect(error.code == .invalidFormalDeclaration)
            #expect(error.description.contains("nextSequence"))
            #expect(error.description.contains("'\(requested)'"))
        }
    }

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

    @Test("changing a parameter label preserves compiled identity",
        arguments: ["limit", "IF", "LET", "CONSTANTS", "TRUE", "FALSE", "BOOLEAN", "STRING"])
    func labelIsPresentationOnly(name: String) throws {
        func compile(_ label: String) throws -> CompiledSpecification {
            try SpecParser.parseSpecClosure(named: "ParameterIdentity", parseSpecTestClosure("""
            { scope in let \(name) = scope.parameter(as: Int.self, in: 0...2, label: "\(label)") }
            """)).compile()
        }
        let first = try compile("Visit limit")
        let second = try compile("Maximum visits")
        #expect(first.identity == second.identity)
        #expect(first.description.parameters.first?.name == name)
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
