import Testing
@testable import SwiftTLA
@testable import SwiftTLAPlugin

struct StateDeclarationNamesTests {
    @Test("key-path refinement mappings bind source declarations before formal renaming",
        arguments: [false, true], ["KeepsSource", "Len", "Spec"])
    func retainsRefinementSourceNames(projecting: Bool, claimName: String) throws {
        let instance = Instance(_name: "abstract", of: FairRefinementTarget.self) {
            Bind(\FairRefinementTarget.Configuration.N, to: 1)
        }
        func check(_ source: TLASpec, name: String, formalName: String,
                   mapping: GeneratedModelStateMapping<FairRefinementTarget.State>) throws {
            var source = source
            source.generatedModelInstances.append(instance)
            source.generatedRefinements.append(Refinement(_name: claimName, instance: instance) { mapping })
            let compilation = try source.compile()
            let variable = try #require(compilation.layout.testVariableID(named: name))
            let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: compilation))
            #expect(program.layout.generatedRefinementProperties.first?.declaration.name == claimName)
            #expect(!["Len", "Spec"].contains(try #require(program.generatedRefinements.first).name))
            let binding = try #require(program.generatedRefinements.first?.state.first)
            #expect(binding.value.expression.operation == .stateVariable(variable))
            #expect(binding.projected == projecting)
            #expect(try program.renderGeneratedModelValue(binding.value) == formalName)
        }
        let escaped = projecting
            ? Map(\FairRefinementTarget.State.value, from: \EscapedStateNamesModel.State.`default`, projecting: Int.self)
            : Map(\FairRefinementTarget.State.value, from: \EscapedStateNamesModel.State.`default`)
        try check(EscapedStateNamesModel.spec, name: "default", formalName: "default", mapping: escaped)
        let renamed = projecting
            ? Map(\FairRefinementTarget.State.value, from: \BoundStateNamesModel.State.Init, projecting: Int.self)
            : Map(\FairRefinementTarget.State.value, from: \BoundStateNamesModel.State.Init)
        try check(BoundStateNamesModel.spec, name: "Init", formalName: "Init__2", mapping: renamed)
    }

    @Test("state fields keep Swift identity when formal behavior names are occupied")
    func retainsFieldsNamedAfterBehavior() throws {
        for name in ["Init", "Next", "Spec", "TRUE", "FALSE", "Len", "Cardinality", "Int", "Nat", "PrintT", "RandomSubset"] {
            let sibling = name == "Spec" ? "Spec__2" : "count"
            let formalName = ["PrintT", "RandomSubset"].contains(name) ? name
                : name == "Spec" ? "Spec__3" : "\(name)__2"
            let source = try parseSpecTestClosure("""
            { scope in
                let \(name) = scope.sharedVar(initial: 0)
                let \(sibling) = scope.sharedVar(initial: 1)
                Do(TestControlLabel.advance) { Assign(\(name), to: \(name) + 1) }
            }
            """)
            let specification = SpecParser.parseSpecClosure(named: "BoundStateNames", source,
                sourceTypes: .init(enums: [parserTestEnum("TestControlLabel", cases: ["advance": .string("advance")])]))
            try #require(specification.diagnostics.isEmpty)
            let compiled = try specification.compile()
            let variable = try #require(compiled.layout.testVariableID(named: name))
            let runtime = CompiledRuntime(compilation: compiled)
            let initial = try #require(try runtime.initialStates().first)
            #expect(try initial.value(for: variable) == .integer(0))
            let next = try #require(try runtime.successors(from: initial).first)
            #expect(try next.state.value(for: variable) == .integer(1))
            let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: compiled))
            let api = try GeneratedMachineAPI(layout: program.layout, actions: program.behavior.actions)
            #expect(api.variables.first?.argumentLabel == name)
            let token = try #require(TLAStateProjection.Token(validating: formalName))
            let siblingToken = try #require(TLAStateProjection.Token(validating: sibling))
            let projected = try initial.projection(using: compiled.layout)
            #expect(projected.value(for: token) == .int(0))
            #expect(projected.value(for: siblingToken) == .int(1))
            var emitter = NativeSwiftEmitter(model: try MacroCompilation(typeName: "BoundStateNames", program: program))
            let native = try emitter.machineMembers().map(\.description).joined(separator: "\n")
            #expect(native.contains(".init(swiftName: \"\(name)\", formalName: \"\(formalName)\")"))
            let output = try compiled.render().tlaBundle.tla
            #expect(output.contains("VARIABLES \(formalName), \(sibling)\n"))
            #expect(output.contains("\(formalName) = 0"))
            #expect(output.contains("\(formalName)' ="))
        }
    }

    @Test("renamed formal fields retain their complete initial failure prefix")
    func retainsRenamedFailurePrefix() throws {
        let source = try parseSpecTestClosure("""
        { scope in
            let Spec = scope.sharedVar(initial: 1)
            let second = scope.sharedVar(initial: Spec + 2)
            let third = scope.sharedVar(initial: second + Int.max)
        }
        """)
        let specification = SpecParser.parseSpecClosure(named: "BoundStateNames", source)
        try #require(specification.diagnostics.isEmpty)
        let compiled = try specification.compile()
        let outcomes = try CompiledRuntime(compilation: compiled).initialOutcomes()
        #expect(outcomes.states.isEmpty)
        #expect(outcomes.failures.count == 1)
        let failure = try #require(outcomes.failures.first)
        #expect(failure.site == .initializer(2))
        let prefix = try failure.formalBindingsBeforeFailure()
        #expect(prefix.entries.count == 2)
        #expect(prefix.value(for: try #require(.init(validating: "Spec__2"))) == .int(1))
        #expect(prefix.value(for: try #require(.init(validating: "second"))) == .int(3))
        #expect(try compiled.render().tlaBundle.tla.contains("[name |-> \"Spec__2\", value |-> "))
    }

    @Test("authored PlusCal uses the same formal state names as direct TLA", arguments: ["Spec", "Len", "Cardinality", "Int", "Nat", "PrintT", "RandomSubset"])
    func retainsFormalNamesInAuthoredExport(name: String) throws {
        let imports = ["PrintT": "Extends(.tlc)", "RandomSubset": "Extends(.randomization)"][name] ?? ""
        let source = try parseSpecTestClosure("""
        {
            \(imports)
            let workers = Algorithm(label: "Workers", scoped: { scope in
                let \(name) = scope.sharedVar(initial: 0)
                Do(TestControlLabel.advance) { Assign(\(name), to: \(name) + 1) }
            })
            workers
        }
        """)
        let specification = SpecParser.parseSpecClosure(named: "BoundStateNames", source,
            sourceTypes: .init(enums: [parserTestEnum("TestControlLabel", cases: ["advance": .string("advance")])]))
        try #require(specification.diagnostics.isEmpty)
        let compiled = try specification.compile()
        let variable = try #require(compiled.layout.testVariableID(named: name))
        let runtime = CompiledRuntime(compilation: compiled)
        let initial = try #require(try runtime.initialStates().first)
        #expect(try initial.value(for: variable) == .integer(0))
        let next = try #require(try runtime.successors(from: initial).first)
        #expect(try next.state.value(for: variable) == .integer(1))
        let program = try CompiledProgram(inputs: SourceTypeResolver().resolve(in: compiled))
        let module = try program.renderModule()
        let authored = try #require(try program.renderAuthoredPlusCal(declarations: module))
        let formalName = "\(name)__2"
        #expect(module.renderedModuleSource.contains("VARIABLES pc, \(formalName)\n"))
        #expect(authored.contains("\(formalName) = 0"))
        #expect(authored.contains("\(formalName) :="))
        #expect(!authored.contains("\(name) :="))
    }

    @Test("a state named vars retains its value without a conflicting generated tuple alias")
    func retainsVarsStateName() throws {
        let source = try parseSpecTestClosure("""
        { scope in
            let vars = scope.sharedVar(initial: 0)
            let count = scope.sharedVar(initial: 1)
        }
        """)
        let specification = SpecParser.parseSpecClosure(named: "BoundStateNames", source)
        try #require(specification.diagnostics.isEmpty)
        let compiled = try specification.compile()
        let runtime = CompiledRuntime(compilation: compiled)
        let initial = try #require(try runtime.initialStates().first)
        let variable = try #require(compiled.layout.testVariableID(named: "vars"))
        #expect(try initial.value(for: variable) == .integer(0))
        let output = try compiled.render().tlaBundle.tla
        #expect(output.contains("VARIABLES vars, count\n"))
        #expect(!output.split(separator: "\n").contains { $0.hasPrefix("vars ==") })
        #expect(output.contains("[][Next]_<<vars, count>>"))
    }

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
        #expect(names.isSuperset(of: ["text", "Init", "seen"]))
        #expect(!names.contains("payload"))
        let displayNames = Dictionary(uniqueKeysWithValues: compiled.description.variables.map { ($0.name, $0.displayName) })
        #expect(displayNames["text"] == "Current text")
        #expect(displayNames["Init"] == "Current text")
        #expect(displayNames["seen"] == "Visited?")
        #expect(BoundStateNamesModel.State.displayNames[\BoundStateNamesModel.State.text] == "Current text")
        #expect(BoundStateNamesModel.State.displayNames[\BoundStateNamesModel.State.Init] == "Current text")
        #expect(BoundStateNamesModel.State.fieldIdentities[\BoundStateNamesModel.State.Init]?.swiftName == "Init")
        #expect(BoundStateNamesModel.State.fieldIdentities[\BoundStateNamesModel.State.Init]?.formalName == "Init__2")
        let machines = try BoundStateNamesModel.initialMachines()
        #expect(machines.count == 2)
        #expect(Set(machines.map(\.state.Init)) == [0, 1])
        for machine in machines {
            #expect(machine.state.text == "payload")
            let token = try #require(TLAStateProjection.Token(validating: "Init__2"))
            #expect(try machine.formalProjection(of: machine.snapshot).value(for: token) == .int(machine.state.Init))
            let successors = try machine.successors()
            #expect(successors.count == 1)
            #expect(successors.first?.machine.state.text == "visited")
            #expect(successors.first?.machine.state.Init == machine.state.Init + 1)
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
