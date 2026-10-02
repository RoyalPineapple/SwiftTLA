import Testing
@testable import SwiftTLA
@testable import SwiftTLAPlugin

struct StateDeclarationNamesTests {
    @Test("escaped Swift declarations retain unescaped model identities")
    func resolvesEscapedStateNames() throws {
        let compiled = try EscapedStateNamesModel.spec.compile()
        let names = Set(compiled.layout.variables.map(\.declaration.name))
        #expect(names.isSuperset(of: ["repeat", "default", "case"]))
        #expect(names.allSatisfy { !$0.contains("`") })
        let scenario = try #require(EscapedStateNamesModel.validationScenarios().first)
        #expect(EscapedStateNamesModel.formalPropertyNames[.`defer`] == "defer")
        #expect(EscapedStateNamesModel.State.displayNames[\EscapedStateNamesModel.State.`repeat`] == "repeat")
        let initial = try #require(scenario.initialMachines().first)
        #expect(initial.state.`repeat` == "payload")
        #expect(initial.state.`default` == 1)
        let next = try #require(initial.successors().first?.machine)
        #expect(next.state.`repeat` == "visited")
        #expect(next.state.`default` == 2)
    }

    @Test("mutable state-handle bindings fail before lowering")
    func rejectsMutableStateHandle() throws {
        let source = try parseSpecTestClosure("""
        {
            let counter = Algorithm(label: "Counter", scoped: { scope in
                var count = scope.sharedVar(initial: 0)
                Do("advance") { Assign(count, to: count + 1) }
            })
            counter
        }
        """)
        let spec = SpecParser.parseSpecClosure(named: "MutableHandle", source)
        #expect(!spec.diagnostics.isEmpty)
        #expect(throws: (any Error).self) { try spec.compile() }
    }

    @Test("anonymous state declarations require a named Swift binding")
    func rejectsAnonymousStateDeclaration() throws {
        for source in [
            "{ scope in scope.sharedVar(initial: 0) }",
            "{ let counter = Algorithm(label: \"Counter\", scoped: { scope in scope.sharedVar(initial: 0) }); counter }"
        ] {
            let spec = SpecParser.parseSpecClosure(named: "AnonymousState", try parseSpecTestClosure(source))
            let diagnostic = try #require(spec.diagnostics.first)
            #expect(diagnostic.message.contains("A state handle must be an immutable named let binding."))
            #expect(diagnostic.sourceSpan.location != .unavailable)
            #expect(throws: SourceParseDiagnostic.self) { try spec.compile() }
        }
    }

    @Test("state labels require one nonempty literal at the declaration")
    func rejectsInvalidStateDisplayLabels() throws {
        for argument in ["1", "\"\"", "\"count \\(1)\"", "\"one\", label: \"two\""] {
            let spec = SpecParser.parseSpecClosure(named: "InvalidStateLabel", try parseSpecTestClosure("""
            { scope in let count = scope.sharedVar(label: \(argument), initial: 0) }
            """))
            let diagnostic = try #require(spec.diagnostics.first)
            #expect(diagnostic.message == "A state label requires one nonempty string literal without interpolation.")
            #expect(diagnostic.sourceSpan.location != .unavailable)
            #expect(throws: SourceParseDiagnostic.self) { try spec.compile() }
        }
    }

    @Test("invalid state labels fail in an external Swift consumer")
    func rejectsInvalidSwiftStateLabels() throws {
        let build = try buildExternalConsumer("InvalidStateDisplayLabel")
        #expect(build.status != 0)
        let diagnostics = build.output.split(separator: "\n").filter {
            $0.contains("A state label requires one nonempty string literal without interpolation.")
        }
        #expect(!diagnostics.isEmpty, "Expected a state-label diagnostic: \(build.output)")
        #expect(build.output.contains("InvalidStateDisplayLabel.swift:9:"))
    }

    @Test("scoped state names derive from Swift bindings across builder scopes")
    func derivesStateNames() throws {
        let compiled = try BoundStateNamesModel.spec.compile()
        let names = Set(compiled.layout.variables.map(\.declaration.name))
        #expect(names.isSuperset(of: ["text", "count", "seen"]))
        #expect(!names.contains("payload"))
        let displayNames = Dictionary(uniqueKeysWithValues: compiled.description.variables.map { ($0.name, $0.displayName) })
        #expect(displayNames["text"] == "Current text")
        #expect(displayNames["count"] == "Current text")
        #expect(displayNames["seen"] == "Visited?")
        #expect(BoundStateNamesModel.State.displayNames[\BoundStateNamesModel.State.text] == "Current text")
        #expect(BoundStateNamesModel.State.displayNames[\BoundStateNamesModel.State.count] == "Current text")
        let machines = try BoundStateNamesModel.initialMachines()
        #expect(machines.count == 2)
        #expect(Set(machines.map(\.state.count)) == [0, 1])
        for machine in machines {
            #expect(machine.state.text == "payload")
            let successors = try machine.successors()
            #expect(successors.count == 1)
            #expect(successors.first?.machine.state.text == "visited")
            #expect(successors.first?.machine.state.count == machine.state.count + 1)
        }
    }

    @Test("changing a state display label leaves formal identity unchanged")
    func stateLabelsArePresentationOnly() throws {
        func compile(_ label: String) throws -> CompiledSpecification {
            try SpecParser.parseSpecClosure(named: "LabelIdentity", parseSpecTestClosure("""
            { scope in let count = scope.sharedVar(label: "\(label)", initial: 0) }
            """)).compile()
        }
        let first = try compile("Count")
        let second = try compile("Number of visits")
        #expect(first.identity == second.identity)
        #expect(try first.render().tlaBundle.tla == second.render().tlaBundle.tla)
        #expect(try !second.render().tlaBundle.tla.contains("Number of visits"))
        #expect(first.description.variables.map(\.name) == second.description.variables.map(\.name))
        #expect(first.description.variables.first?.displayName == "Count")
        #expect(second.description.variables.first?.displayName == "Number of visits")
    }
}
