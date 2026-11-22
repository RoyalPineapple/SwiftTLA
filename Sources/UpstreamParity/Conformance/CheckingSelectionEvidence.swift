import Foundation
import SwiftParser
import SwiftSyntax
import SwiftTLA
import SwiftTLACompilerSupport

package enum CheckingSelectionEvidence {
    private struct Declaration {
        let binding: String
        let name: String
        let kind: CompiledDeclaration.Kind
        let floor: (field: String, minimum: Int)?
    }

    private struct AuthoredSelection {
        let declarations: [Declaration]
        let handles: [String]
        let deadlockOverrides: [Bool]
    }

    package static func prepare(authoredSource: Data, to output: URL, branchwise: Bool = false) throws {
        if branchwise {
            try prepare(authoredSource: authoredSource, to: output,
                modelName: "BranchwiseConjunctionFailureOrderModel", spec: BranchwiseConjunctionFailureOrderModel.spec,
                scenarios: BranchwiseConjunctionFailureOrderModel.validationScenarios(), branchwise: true)
        } else {
            try prepare(authoredSource: authoredSource, to: output,
                modelName: "SelectedChecksModel", spec: SelectedChecksModel.spec,
                scenarios: SelectedChecksModel.validationScenarios(), branchwise: false)
        }
    }

    private static func prepare<Scenario: ModelValidationScenario>(authoredSource: Data, to output: URL,
        modelName: String, spec source: TLASpec, scenarios: [Scenario], branchwise: Bool) throws {
        guard let sourceText = String(data: authoredSource, encoding: .utf8),
              !sourceText.utf8.contains(0) else { throw invalid("authored model bytes") }
        let authored = try authoredSelection(in: sourceText, modelName: modelName, needsInvariantFloors: branchwise)
        let compiled = try source.compile()
        let scenario = try unique(scenarios.filter { $0.name == "Selected" }, "native scenario")
        let compiledScenario = try unique(compiled.semantics.behavior.validationScenarios.filter {
            $0.name == scenario.name
        }, "compiled scenario")
        let rendered = try scenario.render()
        let inputs = try CompiledTypeInputs(compilation: compiled,
            types: CompiledTypeContext(enums: .init(), formalNames: [:])) { spelling in
                guard ["Int", "Swift.Int"].contains(spelling) else { throw invalid("state type") }
                return .int
            }
        let program = try CompiledProgram(inputs: inputs)
        let compilerRender = try program.renderModule()
        let root = rendered.tlaBundle.root
        guard case .compiled(let identity, _, _) = rendered.tlaBundle.provenance
        else { throw invalid("configured render provenance") }
        guard identity == program.identity else { throw invalid("configured render compilation identity") }
        guard rendered.tlaBundle.imports.isEmpty, compilerRender.imports.isEmpty
        else { throw invalid("configured render imports") }
        guard root.name == compilerRender.moduleName else { throw invalid("configured render module name") }
        guard root.tla.utf8.elementsEqual(compilerRender.renderedModuleSource.utf8)
        else { throw invalid("configured render TLA bytes") }
        guard rendered.actions == compilerRender.renderedActions else { throw invalid("configured render action inventory") }
        guard let cfg = root.cfg else { throw invalid("configured render has no CFG") }
        guard scenario.checkingMode == .exhaustive else { throw invalid("configured render checking mode") }
        guard scenario.behavior == .specification else { throw invalid("configured render behavior") }
        guard !scenario.usesView else { throw invalid("configured render view") }
        guard scenario.postconditionName == nil else { throw invalid("configured render postcondition") }
        let actionTotality: SelectedActionFailureEvidence.Input?
        if branchwise {
            actionTotality = nil
        } else {
            actionTotality = try SelectedActionFailureEvidence.input(
                authoredText: sourceText, spec: source, program: program, rendered: compilerRender)
        }
        let authoredByName = try Dictionary(authored.declarations.map { ($0.name, $0.binding) },
            uniquingKeysWith: { _, _ in throw invalid("duplicate authored property name") })
        let propertyReferences = source.invariants.map { ($0.name, $0.reference) }
            + source.reachabilityProperties.map { ($0.name, $0.reference) }
            + source.temporalProperties.map { ($0.name, $0.reference) }
        var registered: [PropertyReference: String] = [:]
        for (name, reference) in propertyReferences {
            guard let reference, let binding = authoredByName[name],
                  registered.updateValue(binding, forKey: reference) == nil else { throw invalid("registered property references") }
        }
        let catalog = try compiled.layout.properties.map { property -> TLAValue in
            let reference: String
            if let handle = property.reference {
                guard let binding = registered[handle] else { throw invalid("unowned compiled property reference") }
                reference = binding
            } else {
                reference = ""
            }
            return record([
                ("name", .string(property.declaration.name)), ("kind", .string(property.declaration.kind.rawValue)),
                ("ref", .string(reference)), ("ordinal", .int(property.id.ordinal)), ("formal", .string(property.formalName)),
            ])
        }

        let nativeCases = Array(Scenario.Property.allCases)
        let nativeOrdinals = try Dictionary(nativeCases.enumerated().map { ($0.element, $0.offset) },
            uniquingKeysWith: { _, _ in throw invalid("duplicate native property identity") })
        let nativeCatalog = try nativeCases.map { property -> TLAValue in
            guard let name = scenario.formalPropertyNames[property] else { throw invalid("native formal property projection") }
            return .string(name)
        }
        let nativeSelected = try scenario.checking.properties.map { property -> TLAValue in
            guard let ordinal = nativeOrdinals[property] else { throw invalid("native selected property case") }
            return .int(ordinal)
        }
        let nativeInvariants = try nativeIDs(Scenario.Machine.invariantProperties, ordinals: nativeOrdinals)
        let nativeReachability = try nativeIDs(Scenario.Machine.reachabilityProperties, ordinals: nativeOrdinals)
        let complete = try configurationChecks(cfg)
        let authoredRows = authored.declarations.map {
            record([("binding", .string($0.binding)), ("name", .string($0.name)), ("kind", .string($0.kind.rawValue))])
        }
        let physical = try physicalSelection(configuration: complete, rendered: rendered,
            actionLines: actionTotality?.actionLines ?? [])
        let initial = try scenario.initialOutcomes()
        guard initial.firstFailure == nil else { throw invalid("native initialization failure") }
        let fairness = try initial.states.first.map { try scenario.fairnessConditions(on: $0) } ?? []
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: false)
        let nativeGraph = output.appendingPathComponent(root.name + ".native.bin")
        let nativeProfile = nativeGraph.deletingPathExtension().appendingPathExtension("profile.json")
        var observed = BranchwiseCheckingHistory<Scenario.Machine>()
        let observer: ((MachineValidationEvent<Scenario.Machine>) throws -> Void)?
        if branchwise, let machine = initial.states.first {
            observer = { event in try observed.observe(event, machine: machine, program: program) }
        } else { observer = nil }
        let nativeRun = try MachineValidationEvidence.write(scenario: scenario, initialMachines: initial.states,
            caseID: scenario.name, maximumStates: branchwise ? 32 : 16, stopOnViolation: false, stopOnReachability: false,
            fairness: fairness, to: nativeGraph, observe: observer)
        let nativeCompleted: Bool
        switch nativeRun.completion {
        case .exhausted: nativeCompleted = !branchwise
        case .evaluationFailure: nativeCompleted = branchwise
        default: nativeCompleted = false
        }
        guard nativeCompleted, nativeRun.states > 0, let orderedHistory = nativeRun.orderedActionFailureHistory
        else { throw invalid("native complete ordered action history") }
        let nativeHistory: String
        let supplementalEvidence: String
        let proofName: String
        let proof: String
        if branchwise {
            nativeHistory = "BranchwiseNativeHistory"
            supplementalEvidence = try observed.definitions(history: orderedHistory, summary: nativeRun,
                names: scenario.formalPropertyNames, program: program)
                + "\n" + branchwiseInvariantDefinitions(authored.declarations, program: program, module: root.name)
            proofName = "SwiftTLABranchwiseCheckingInputs"
            proof = selectionProof + "\n\n" + branchwiseSelectionProof
        } else {
            nativeHistory = TLAValue.tuple(orderedHistory.map(orderedFailureOccurrence)).description
            supplementalEvidence = actionTotality?.definitions ?? ""
            proofName = "SwiftTLAActualCheckingSelection"
            proof = selectionProof + "\n\n" + selectedScalarProof
        }
        let definitions = """
        ---- MODULE \(proofName) ----
        EXTENDS Integers, Sequences, TLAPS, \(physical.imports)

        \(physical.pageReferences)
        \(physical.definitions)
        \(supplementalEvidence)

        AuthoredProperties == \(TLAValue.tuple(authoredRows))
        AuthoredSelectedHandles == \(TLAValue.set(Set(authored.handles.map(TLAValue.string))))
        AuthoredDeadlockOverrides == \(TLAValue.tuple(authored.deadlockOverrides.map(TLAValue.bool)))
        SourceDeadlockDefault == \(TLAValue.bool(source.checkDeadlock))
        AuthoredDeadlockChoice == \(TLAValue.bool(authored.deadlockOverrides.first ?? source.checkDeadlock))
        ActualCompiledCatalog == \(TLAValue.tuple(catalog))
        ActualCompiledChecks == \(TLAValue.set(Set(compiledScenario.checks.map { .int($0.ordinal) })))
        ActualCompiledDeadlock == \(TLAValue.bool(compiledScenario.checkDeadlock))
        ActualNativeCatalog == \(TLAValue.tuple(nativeCatalog))
        ActualNativeChecks == \(TLAValue.set(Set(nativeSelected)))
        ActualNativeInvariants == \(nativeInvariants)
        ActualNativeReachability == \(nativeReachability)
        ActualNativeDeadlock == \(TLAValue.bool(scenario.checking.checkDeadlock))
        ActualCFGIntrinsicInvariants == \(TLAValue.set(Set(rendered.intrinsicInvariantNames.map(TLAValue.string))))
        ActualRendererInvariants == \(TLAValue.set(Set(rendered.invariantNames.map(TLAValue.string))))
        ActualRendererReachability == \(TLAValue.set(Set(rendered.reachabilityNames.map(TLAValue.string))))
        ActualNativeExhausted == \(TLAValue.bool(nativeCompleted))
        ActualNativeVisitedStates == \(TLAValue.int(nativeRun.states))
        ActualNativeOrderedActionHistory == \(nativeHistory)

        \(proof)
        ====

        """
        let files = [
            "authored-model.swift": authoredSource,
            root.name + ".tla": Data(root.tla.utf8),
            root.name + ".cfg": Data(cfg.utf8),
            (proofName + ".tla"): Data(definitions.utf8),
        ]
        for (name, contents) in files {
            try contents.write(to: output.appendingPathComponent(name), options: .atomic)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        var hashes = files.mapValues(SHA256.hex)
        for artifact in [nativeGraph, nativeProfile] {
            hashes[artifact.lastPathComponent] = SHA256.hex(try Data(contentsOf: artifact))
        }
        try encoder.encode(hashes).write(to: output.appendingPathComponent("files.json"), options: .atomic)
    }

    private static func orderedFailureOccurrence(_ occurrence: ValidationActionFailureOccurrence) -> TLAValue {
        let failure = occurrence.failure
        let payload = BinaryEvaluationFailure(failure.reason)
        let before = TLAValue.tuple(failure.before.map { binding in
            record([("binding", .int(binding.binding)), ("target", .int(binding.target)), ("value", .int(binding.value))])
        })
        let event = record([
            ("branch", .int(failure.branch)), ("site", .int(failure.site)), ("target", .int(failure.target)),
            ("before", before), ("payload", record([
                ("code", .int(Int(payload.code))), ("detail", .string(payload.detail)),
                ("integers", .tuple(payload.integers.map(TLAValue.int))),
            ])),
        ])
        return .tuple([.int(occurrence.source), .int(failure.action), event])
    }

    private static func nativeIDs<Property: Hashable>(
        _ properties: [Property], ordinals: [Property: Int]
    ) throws -> TLAValue {
        try .set(Set(properties.map { property -> TLAValue in
            guard let ordinal = ordinals[property] else { throw invalid("native property kind") }
            return .int(ordinal)
        }))
    }

    private static func record(_ fields: [(String, TLAValue)]) -> TLAValue {
        .record(TLARecord(fields.map { .init($0.0, $0.1) }))
    }

    private static func unique<Value>(_ candidates: [Value], _ role: String) throws -> Value {
        guard candidates.count == 1, let value = candidates.first else { throw invalid(role) }
        return value
    }

    private static func invalid(_ role: String) -> EvidenceFormatError {
        .invalidField(record: "SelectedChecks", field: role)
    }

    private static func authoredSelection(in text: String, modelName: String, needsInvariantFloors: Bool) throws -> AuthoredSelection {
        let source = Parser.parse(source: text)
        guard !source.hasError else { throw invalid("authored syntax") }
        let model = try unique(source.statements.compactMap { $0.item.as(StructDeclSyntax.self) }.filter {
            $0.name.text == modelName
        }, "authored model declaration")
        guard let specification = try ModelSpecificationSyntax.find(in: model.memberBlock.members, defaultName: modelName)
        else { throw invalid("authored specification") }
        var declared: [String: Declaration] = [:]
        var registered: [Declaration] = []
        var scenarios: [ExprSyntax] = []
        let kinds: [String: CompiledDeclaration.Kind] = [
            "Invariant": .invariant, "Reachable": .reachability, "Always": .temporalProperty,
        ]
        var selectedRegistrationCount = 0
        for item in specification.closure.statements {
            if let variable = item.item.as(VariableDeclSyntax.self), variable.bindingSpecifier.text == "let",
               variable.bindings.count == 1, let binding = variable.bindings.first,
               let token = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier,
               let initializer = binding.initializer?.value {
                let name = identifier(token)
                if name == "Selected" { scenarios.append(initializer) }
                if let call = initializer.as(FunctionCallExprSyntax.self),
                   let function = reference(call.calledExpression), let kind = kinds[function] {
                    guard let first = call.arguments.first, first.label == nil,
                          let nameLiteral = first.expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue
                    else { throw invalid("authored property declaration") }
                    let floor = needsInvariantFloors ? try invariantFloor(call, kind: kind) : nil
                    guard declared.updateValue(.init(binding: name, name: nameLiteral, kind: kind, floor: floor),
                                               forKey: name) == nil else { throw invalid("authored property declaration") }
                }
                continue
            }
            if let name = reference(item.item.as(ExprSyntax.self)) {
                if let property = declared[name] { registered.append(property) }
                if name == "Selected", !scenarios.isEmpty { selectedRegistrationCount += 1 }
            }
        }
        guard selectedRegistrationCount == 1, !registered.isEmpty,
              Set(registered.map(\.binding)).count == registered.count,
              Set(registered.map(\.name)).count == registered.count else { throw invalid("authored property registration") }
        let scenario = try unique(scenarios, "authored scenario declaration")
        var remaining = scenario
        var properties: [String]?
        var overrides: [Bool] = []
        while let call = remaining.as(FunctionCallExprSyntax.self),
              let member = call.calledExpression.as(MemberAccessExprSyntax.self),
              let base = member.base {
            guard call.trailingClosure == nil, call.additionalTrailingClosures.isEmpty,
                  call.arguments.count == 1, let argument = call.arguments.first else { throw invalid("authored selection modifier") }
            switch identifier(member.declName.baseName) {
            case "checking":
                guard properties == nil, argument.label?.text == "only",
                      let array = argument.expression.as(ArrayExprSyntax.self) else { throw invalid("authored checking(only:)") }
                properties = try array.elements.map { element in
                    guard let name = reference(element.expression),
                          registered.contains(where: { $0.binding == name }) else { throw invalid("authored selected handle") }
                    return name
                }
            case "checkingDeadlock":
                guard overrides.isEmpty, argument.label == nil,
                      let flag = argument.expression.as(BooleanLiteralExprSyntax.self) else { throw invalid("authored checkingDeadlock") }
                overrides.append(flag.literal.text == "true")
            default:
                throw invalid("authored scenario modifier")
            }
            remaining = base
        }
        guard let constructor = remaining.as(FunctionCallExprSyntax.self),
              reference(constructor.calledExpression) == "Validation", constructor.arguments.isEmpty,
              constructor.additionalTrailingClosures.isEmpty, constructor.trailingClosure?.statements.isEmpty == true,
              let properties, Set(properties).count == properties.count else { throw invalid("authored Selected scenario") }
        let catalog = registered.filter { $0.kind == .invariant }
            + registered.filter { $0.kind == .reachability }
            + registered.filter { $0.kind == .temporalProperty }
        return .init(declarations: catalog, handles: properties, deadlockOverrides: overrides)
    }

    private static func invariantFloor(_ call: FunctionCallExprSyntax, kind: CompiledDeclaration.Kind)
        throws -> (field: String, minimum: Int) {
        guard kind == .invariant, call.arguments.count == 1, call.additionalTrailingClosures.isEmpty,
              let statements = call.trailingClosure?.statements, statements.count == 1,
              let expression = statements.first?.item.as(SequenceExprSyntax.self) else {
            throw invalid("authored branchwise invariant")
        }
        let operands = Array(expression.elements)
        guard operands.count == 3, let field = reference(operands[0]),
              operands[1].as(BinaryOperatorExprSyntax.self)?.operator.text == ">=",
              let minimum = Int(operands[2].trimmedDescription) else {
            throw invalid("authored branchwise integer floor")
        }
        return (field, minimum)
    }

    private static func branchwiseInvariantDefinitions(_ declarations: [Declaration],
        program: CompiledProgram, module: String) throws -> String {
        let fields = program.layout.variables
        guard asciiIdentifier(module), !fields.isEmpty,
              fields.allSatisfy({ asciiIdentifier($0.formalName) && program.variableTypes[$0.id] == .int })
        else { throw invalid("branchwise formal invariant state") }
        let substitutions = fields.enumerated().map { index, field in
            "\(field.formalName) <- snapshot[\(index + 1)]"
        }.joined(separator: ", ")
        var rows: [TLAValue] = []
        var dispatch: [String] = []
        var predicateDefinitions: [String] = []
        for declaration in declarations {
            guard let floor = declaration.floor else { throw invalid("branchwise authored invariant floor") }
            let index = try unique(fields.indices.filter {
                fields[$0].declaration.name.utf8.elementsEqual(floor.field.utf8)
            }, "branchwise authored invariant read")
            let property = try unique(program.layout.properties.filter {
                $0.declaration.kind == .invariant && $0.declaration.name.utf8.elementsEqual(declaration.name.utf8)
            }, "branchwise formal invariant")
            guard asciiIdentifier(property.formalName) else { throw invalid("branchwise formal invariant identifier") }
            rows.append(record([
                ("name", .string(declaration.name)), ("position", .int(index + 1)), ("minimum", .int(floor.minimum)),
            ]))
            dispatch.append("property = \(TLAValue.string(declaration.name)) -> BranchwisePredicates(snapshot)!\(property.formalName)")
            predicateDefinitions.append("BranchwisePredicates!\(property.formalName)")
        }
        let cases = (dispatch + ["OTHER -> FALSE"]).joined(separator: " [] ")
        return #"""
        BranchwiseAuthoredInvariantRows == \#(TLAValue.tuple(rows))
        BranchwisePredicates(snapshot) == INSTANCE \#(module) WITH \#(substitutions)
        BranchwiseAuthoredInvariantNames ==
            {BranchwiseAuthoredInvariantRows[index].name : index \in DOMAIN BranchwiseAuthoredInvariantRows}
        BranchwiseAuthoredClaim(property, snapshot) ==
            LET index == CHOOSE i \in DOMAIN BranchwiseAuthoredInvariantRows : BranchwiseAuthoredInvariantRows[i].name = property
                row == BranchwiseAuthoredInvariantRows[index]
            IN snapshot[row.position] >= row.minimum
        BranchwiseActualTLAClaim(property, snapshot) == CASE \#(cases)
        BranchwiseActualTLAEvaluationOK(snapshot) == BranchwisePredicates(snapshot)!__SwiftTLAEvaluationOK

        THEOREM BranchwiseActualPropertyDenotationsMatchAuthoredFloors ==
            \A property \in BranchwiseAuthoredInvariantNames :
                \A snapshot : BranchwiseActualTLAClaim(property, snapshot) = BranchwiseAuthoredClaim(property, snapshot)
        BY ONLY SMT DEF BranchwiseActualTLAClaim, BranchwiseAuthoredClaim, BranchwiseAuthoredInvariantNames,
            BranchwiseAuthoredInvariantRows, \#(predicateDefinitions.joined(separator: ", "))
        """#
    }

    private static func reference(_ expression: ExprSyntax?) -> String? {
        expression?.as(DeclReferenceExprSyntax.self).map { identifier($0.baseName) }
    }

    private static func identifier(_ token: TokenSyntax) -> String { token.identifier?.name ?? token.text }

    private struct CheckingConfiguration {
        let invariants: [String]
        let properties: [String]
        let deadlock: Bool
    }

    private static func configurationChecks(_ cfg: String) throws -> CheckingConfiguration {
        let lines = cfg.split(separator: "\n")
        guard lines.count >= 2, lines[0] == "SPECIFICATION Spec",
              lines[1] == "CHECK_DEADLOCK TRUE" || lines[1] == "CHECK_DEADLOCK FALSE",
              cfg.utf8.elementsEqual((lines.joined(separator: "\n") + "\n").utf8)
        else { throw invalid("CFG header or line coverage") }
        var invariants: [String] = []
        var properties: [String] = []
        for directive in lines.dropFirst(2) {
            let parts = directive.split(separator: " ", omittingEmptySubsequences: false)
            guard parts.count == 2, let name = parts.last.map(String.init), asciiIdentifier(name)
            else { throw invalid("CFG directive symbol") }
            switch parts[0] {
            case "INVARIANT" where properties.isEmpty: invariants.append(name)
            case "PROPERTY": properties.append(name)
            default: throw invalid("CFG directive")
            }
        }
        let names = invariants + properties
        guard Set(names).count == names.count else { throw invalid("duplicate CFG property") }
        return .init(invariants: invariants, properties: properties, deadlock: lines[1] == "CHECK_DEADLOCK TRUE")
    }

    private static func asciiIdentifier(_ value: String) -> Bool {
        value.range(of: "^[A-Za-z_][A-Za-z_0-9]*$", options: .regularExpression) != nil
    }

    private static func byteVector(_ bytes: some Sequence<UInt8>) -> TLAValue {
        .tuple(bytes.map { .int(Int($0)) })
    }

    private static func physicalSelection(configuration: CheckingConfiguration, rendered: RenderedSpecification,
                                          actionLines: [String]) throws
        -> (imports: String, pageReferences: String, definitions: String) {
        let cfgRows = configuration.invariants.map { (kind: "INVARIANT", name: $0) }
            + configuration.properties.map { (kind: "PROPERTY", name: $0) }
        let cfgLines = ["SPECIFICATION Spec\n",
                        "CHECK_DEADLOCK \(configuration.deadlock ? "TRUE" : "FALSE")\n"]
            + cfgRows.map { "\($0.kind) \($0.name)\n" }
        let cfgLineBytes = cfgLines.map { Array($0.utf8) }
        let cfgBytes = cfgLineBytes.flatMap { $0 }
        let directives = cfgRows.map { row in
            record([("kind", .string(row.kind)), ("name", .string(row.name)), ("symbol", byteVector(row.name.utf8))])
        }
        let cfgExpressions = ["CFGSpecificationLine", "CFGDeadlockLine"] + directives.indices.map {
            "CFGCheckingLine(CFGCheckingRows[\($0 + 1)])"
        }
        let cfgPages = Array(1...((cfgBytes.count + 15) / 16))
        let tlaBytes = Array(rendered.tlaBundle.root.tla.utf8)
        var tlaPages: Set<Int> = []
        func span(name: String, checking needle: [UInt8]) throws -> TLAValue {
            let offset = try unique(tlaBytes.indices.filter { index in
                index + needle.count <= tlaBytes.count && tlaBytes[index..<(index + needle.count)].elementsEqual(needle)
            }, "rendered declaration span")
            tlaPages.formUnion((offset / 16 + 1)...((offset + needle.count - 1) / 16 + 1))
            return record([("name", .string(name)), ("offset", .int(offset)), ("prefix", byteVector(needle))])
        }
        let spans = try rendered.reachabilityNames.sorted().map { name -> TLAValue in
            guard asciiIdentifier(name) else { throw invalid("rendered reachability identifier") }
            return try span(name: name, checking: Array("\n\(name) == ~(".utf8))
        }
        let actionSpans = try actionLines.map { declaration -> TLAValue in
            let name = declaration.prefix { $0 != " " }
            return try span(name: String(name), checking: Array("\n\(declaration)\n".utf8))
        }
        func references(_ prefix: String, pages: [Int]) -> [String] {
            pages.map { "\(prefix)Page\($0)" }
        }
        func blocks(_ prefix: String, pages: [Int]) -> [String] {
            Set(pages.map { ($0 - 1) / 64 + 1 }).sorted().map { "\(prefix)PageBlock\($0)" }
        }
        let cfgBlocks = blocks("CallerInput", pages: cfgPages)
        let tlaBlocks = blocks("CompilerInput", pages: tlaPages.sorted())
        var cfgLineDefinitions: [String] = []
        var cfgCases: [String] = []
        var cfgProofs: [String] = []
        var checkedFragments: [String] = []
        for page in cfgPages {
            let offset = (page - 1) * 16
            let end = min(offset + 16, cfgBytes.count)
            let bytes = "CFGExpectedPage\(page)"
            cfgLineDefinitions.append("LOCAL \(bytes) == \(byteVector(cfgBytes[offset..<end]))")
            cfgProofs.append(#"""
            <1>page\#(page). \A index \in \#(offset + 1)..\#(end) :
                CallerInputByte[index - 1] = \#(bytes)[index - \#(offset)]
                <2>offsets. \A j \in 1..\#(end - offset) :
                    CallerInputByte[\#(offset) + j - 1] = \#(bytes)[j]
                    BY ONLY CallerInputPageBlock\#((page - 1) / 64 + 1)AtFileOffsets DEF \#(bytes)
                <2>. QED BY ONLY <2>offsets, SMT
            """#)
        }
        var offset = 0
        for (index, line) in cfgLineBytes.enumerated() {
            let ordinal = index + 1
            let end = offset + line.count
            let grammar = "CFGGrammarLine\(ordinal)"
            let bytes = "CFGExpectedLine\(ordinal)"
            cfgLineDefinitions.append("LOCAL \(grammar) == \(cfgExpressions[index])")
            cfgLineDefinitions.append("LOCAL \(bytes) == \(byteVector(line))")
            cfgCases.append("index \\in \(offset + 1)..\(end) -> \(grammar)[index - \(offset)]")
            if index < 2 {
                let source = index == 0 ? "CFGSpecificationLine" : "CFGDeadlockLine, CFGDeadlockCode"
                cfgProofs.append(#"""
                <1>line\#(ordinal). /\ \#(grammar) = \#(bytes)
                                  /\ DOMAIN \#(grammar) = 1..\#(line.count)
                    <2>bytes. \#(grammar) = \#(bytes)
                        BY ONLY SMT DEF \#(grammar), \#(bytes), \#(source)
                    <2>extent. DOMAIN \#(bytes) = 1..\#(line.count)
                        BY ONLY SMT DEF \#(bytes)
                    <2>. QED BY ONLY <2>bytes, <2>extent, SMT
                """#)
            } else {
                let row = cfgRows[index - 2]
                let keyword = row.kind == "INVARIANT" ? "CFGInvariantPrefix" : "CFGPropertyPrefix"
                let keywordWidth = row.kind.utf8.count + 1
                let nameWidth = row.name.utf8.count
                let name = TLAValue.string(row.name)
                let symbol = byteVector(row.name.utf8)
                cfgProofs.append(#"""
                <1>line\#(ordinal). /\ \#(grammar) = \#(bytes)
                                  /\ DOMAIN \#(grammar) = 1..\#(line.count)
                    <2>. DEFINE row == CFGCheckingRows[\#(index - 1)]
                                prefix == CFGDirectivePrefix(row)
                    <2>row. /\ row.kind = "\#(row.kind)"
                            /\ row.name = \#(name)
                            /\ row.symbol = \#(symbol)
                        BY ONLY IsaM("simp") DEF row, CFGCheckingRows
                    <2>prefix. prefix = \#(keyword)
                        BY ONLY <2>row, SMT DEF prefix, CFGDirectivePrefix
                    <2>functions. /\ prefix \in [1..\#(keywordWidth) -> Int]
                                  /\ row.symbol \in [1..\#(nameWidth) -> Int]
                                  /\ \#(bytes) \in [1..\#(line.count) -> Int]
                        BY ONLY <2>prefix, <2>row, SMT DEF \#(keyword), \#(bytes)
                    <2>widths. /\ prefix \in Seq(Int) /\ Len(prefix) = \#(keywordWidth)
                               /\ row.symbol \in Seq(Int) /\ Len(row.symbol) = \#(nameWidth)
                               /\ \#(bytes) \in Seq(Int) /\ Len(\#(bytes)) = \#(line.count)
                        BY ONLY <2>functions, SeqDef, LenProperties, SMT
                    <2>keywordBytes. \A index \in 1..Len(prefix) : \#(bytes)[index] = prefix[index]
                        BY ONLY <2>prefix, <2>widths, SMT DEF \#(keyword), \#(bytes)
                    <2>nameBytes. \A index \in 1..Len(row.symbol) : \#(bytes)[Len(prefix) + index] = row.symbol[index]
                        BY ONLY <2>row, <2>widths, SMT DEF \#(bytes)
                    <2>newline. \#(bytes)[Len(\#(bytes))] = 10
                        BY ONLY <2>widths, SMT DEF \#(bytes)
                    <2>extent. Len(\#(bytes)) = Len(prefix) + Len(row.symbol) + 1
                        BY ONLY <2>widths, SMT
                    <2>checked. /\ \#(bytes) = (prefix \o row.symbol) \o <<10>>
                                /\ DOMAIN ((prefix \o row.symbol) \o <<10>>) = 1..Len(\#(bytes))
                        <3>prefix. prefix \in Seq(Int)
                            BY ONLY <2>widths
                        <3>symbol. row.symbol \in Seq(Int)
                            BY ONLY <2>widths
                        <3>line. \#(bytes) \in Seq(Int)
                            BY ONLY <2>widths
                        <3>. QED BY ONLY <3>prefix, <3>symbol, <3>line, <2>extent,
                            <2>keywordBytes, <2>nameBytes, <2>newline, CFGLineIsItsCheckedParts
                    <2>grammar. \#(grammar) = (prefix \o row.symbol) \o <<10>>
                        BY ONLY DEF \#(grammar), CFGCheckingLine, row, prefix
                    <2>. QED BY ONLY <2>checked, <2>grammar, <2>widths, SMT
                """#)
            }
            for page in (offset / 16 + 1)...((end - 1) / 16 + 1) {
                let pageOffset = (page - 1) * 16
                let first = max(offset, pageOffset) + 1
                let last = min(end, pageOffset + 16)
                let label = "fragment\(ordinal)page\(page)"
                checkedFragments.append("<1>\(label)")
                cfgProofs.append(#"""
                <1>\#(label). \A index \in \#(first)..\#(last) :
                    ActualCFGBytes[index] = CFGGrammarBytes[index]
                    <2>bytes. \A index \in \#(first)..\#(last) :
                        CFGExpectedPage\#(page)[index - \#(pageOffset)] = \#(bytes)[index - \#(offset)]
                        BY ONLY SMT DEF CFGExpectedPage\#(page), \#(bytes)
                    <2>. QED BY ONLY <1>domain, <1>page\#(page), <1>line\#(ordinal), <2>bytes, SMT
                        DEF ActualCFGBytes, CFGGrammarBytes
                """#)
            }
            offset = end
        }
        let tlaFacts = (tlaBlocks.map { $0 + "AtFileOffsets" } + ["SMT"]).joined(separator: ", ")
        let definitions = #"""
        CFGSpecificationLine == \#(byteVector("SPECIFICATION Spec\n".utf8))
        CFGDeadlockCode == \#(TLAValue.bool(configuration.deadlock))
        CFGDeadlockLine == IF CFGDeadlockCode THEN \#(byteVector("CHECK_DEADLOCK TRUE\n".utf8))
                           ELSE \#(byteVector("CHECK_DEADLOCK FALSE\n".utf8))
        CFGCheckingRows == \#(TLAValue.tuple(directives))
        CFGInvariantPrefix == \#(byteVector("INVARIANT ".utf8))
        CFGPropertyPrefix == \#(byteVector("PROPERTY ".utf8))
        CFGDirectivePrefix(row) == IF row.kind = "INVARIANT" THEN CFGInvariantPrefix ELSE CFGPropertyPrefix
        CFGCheckingLine(row) == (CFGDirectivePrefix(row) \o row.symbol) \o <<10>>
        LOCAL THEOREM CFGLineIsItsCheckedParts ==
            ASSUME NEW prefix \in Seq(Int), NEW symbol \in Seq(Int), NEW line \in Seq(Int),
                   Len(line) = Len(prefix) + Len(symbol) + 1,
                   \A index \in 1..Len(prefix) : line[index] = prefix[index],
                   \A index \in 1..Len(symbol) : line[Len(prefix) + index] = symbol[index],
                   line[Len(line)] = 10
            PROVE /\ line = (prefix \o symbol) \o <<10>>
                  /\ DOMAIN ((prefix \o symbol) \o <<10>>) = 1..Len(line)
        PROOF
        <1>parts. /\ Len(prefix) \in Nat /\ Len(symbol) \in Nat
                  /\ <<10>> \in Seq(Int) /\ Len(<<10>>) = 1
            BY ONLY (prefix \in Seq(Int)), (symbol \in Seq(Int)), SeqDef, LenProperties, SMT
        <1>prefixSymbol. /\ prefix \o symbol \in Seq(Int)
                         /\ Len(prefix \o symbol) = Len(prefix) + Len(symbol)
                         /\ \A index \in 1..(Len(prefix) + Len(symbol)) :
                               (prefix \o symbol)[index] =
                                   IF index <= Len(prefix) THEN prefix[index] ELSE symbol[index - Len(prefix)]
            BY ONLY (prefix \in Seq(Int)), (symbol \in Seq(Int)), ConcatProperties, SMT
        <1>complete. /\ (prefix \o symbol) \o <<10>> \in Seq(Int)
                     /\ Len((prefix \o symbol) \o <<10>>) = Len(line)
                     /\ \A index \in 1..Len(line) :
                           ((prefix \o symbol) \o <<10>>)[index] =
                               IF index <= Len(prefix) + Len(symbol) THEN (prefix \o symbol)[index] ELSE 10
            BY ONLY <1>parts, <1>prefixSymbol, Len(line) = Len(prefix) + Len(symbol) + 1, ConcatProperties, SMT
        <1>entries. \A index \in 1..Len(line) : line[index] = ((prefix \o symbol) \o <<10>>)[index]
            <2>. TAKE index \in 1..Len(line)
            <2>keyword. CASE index <= Len(prefix)
                BY ONLY <2>keyword, index \in 1..Len(line), <1>parts, <1>prefixSymbol, <1>complete,
                    (\A i \in 1..Len(prefix) : line[i] = prefix[i]), SMT
            <2>name. CASE Len(prefix) < index /\ index <= Len(prefix) + Len(symbol)
                BY ONLY <2>name, index \in 1..Len(line), <1>prefixSymbol, <1>complete,
                    (\A i \in 1..Len(symbol) : line[Len(prefix) + i] = symbol[i]), SMT
            <2>newline. CASE index > Len(prefix) + Len(symbol)
                BY ONLY <2>newline, index \in 1..Len(line), <1>complete,
                    Len(line) = Len(prefix) + Len(symbol) + 1, line[Len(line)] = 10, SMT
            <2>. QED BY ONLY <2>keyword, <2>name, <2>newline, SMT
        <1>. QED BY ONLY (line \in Seq(Int)), <1>complete, <1>entries, SeqEqual, LenProperties, SMT

        \#(cfgLineDefinitions.joined(separator: "\n"))
        CFGGrammarBytes ==
            [index \in 1..\#(cfgBytes.count) |-> CASE \#(cfgCases.joined(separator: "\n        [] "))]
        ActualCFGBytes == [index \in 1..CallerInputSize |-> CallerInputByte[index - 1]]
        CFGBytesMatch == ActualCFGBytes = CFGGrammarBytes

        THEOREM ActualCFGBytesHaveExactlyTheCheckingDirectives == CFGBytesMatch
        PROOF
        <1>domain. /\ DOMAIN ActualCFGBytes = 1..\#(cfgBytes.count)
                   /\ DOMAIN CFGGrammarBytes = 1..\#(cfgBytes.count)
            BY ONLY SMT DEF ActualCFGBytes, CFGGrammarBytes, CallerInputSize
        \#(cfgProofs.joined(separator: "\n"))
        <1>entries. \A index \in DOMAIN CFGGrammarBytes : ActualCFGBytes[index] = CFGGrammarBytes[index]
            BY ONLY <1>domain, \#(checkedFragments.joined(separator: ", ")), SMT
        <1>. QED BY ONLY <1>domain, <1>entries, SMT DEF CFGBytesMatch, ActualCFGBytes, CFGGrammarBytes

        CFGSymbolNames(kind) ==
            {CFGCheckingRows[index].name : index \in {i \in DOMAIN CFGCheckingRows : CFGCheckingRows[i].kind = kind}}
        ActualCFGInvariantDirectives == IF CFGBytesMatch THEN CFGSymbolNames("INVARIANT") ELSE {}
        ActualCFGPropertyDirectives == IF CFGBytesMatch THEN CFGSymbolNames("PROPERTY") ELSE {}
        ActualCFGDeadlock == IF CFGBytesMatch THEN CFGDeadlockCode ELSE "unsupported"

        ReachabilityNegationSpans == \#(TLAValue.tuple(spans))
        RenderedBytesAt(span) ==
            \A byte \in DOMAIN span.prefix :
                /\ span.offset + byte - 1 \in 0..(CompilerInputSize - 1)
                /\ CompilerInputByte[span.offset + byte - 1] = span.prefix[byte]
        ActualNegatedReachabilityDefinitions ==
            {ReachabilityNegationSpans[index].name :
                index \in {i \in DOMAIN ReachabilityNegationSpans : RenderedBytesAt(ReachabilityNegationSpans[i])}}

        THEOREM ActualTLAReachabilitySpansStartWithNegation ==
            \A index \in DOMAIN ReachabilityNegationSpans : RenderedBytesAt(ReachabilityNegationSpans[index])
        BY ONLY \#(tlaFacts) DEF RenderedBytesAt, ReachabilityNegationSpans, CompilerInputSize

        RenderedActionDeclarationSpans == \#(TLAValue.tuple(actionSpans))
        THEOREM ActualTLAHasTheCheckedActionDeclarations ==
            \A index \in DOMAIN RenderedActionDeclarationSpans : RenderedBytesAt(RenderedActionDeclarationSpans[index])
        BY ONLY \#(tlaFacts) DEF RenderedBytesAt, RenderedActionDeclarationSpans, CompilerInputSize
        """#
        let pages = references("CallerInput", pages: cfgPages) + references("CompilerInput", pages: tlaPages.sorted())
        let compilerInputs = tlaBlocks.isEmpty ? ["CompilerInputBytes"] : tlaBlocks
        return ((["SequenceTheorems_proofs"] + cfgBlocks + compilerInputs).joined(separator: ", "), "\\* " + pages.joined(separator: " "), definitions)
    }

    private static let selectionProof = #"""
        LOCAL Selection == INSTANCE CheckingSelectionCompilerBinding WITH NoPropertyHandle <- ""
        LOCAL SequenceFacts == INSTANCE SequenceTheorems

        SourceCatalog == [index \in DOMAIN AuthoredProperties |-> AuthoredProperties[index].name]
        Declarations == {AuthoredProperties[index].name : index \in DOMAIN AuthoredProperties}
        Position(property) ==
            CHOOSE index \in DOMAIN AuthoredProperties : AuthoredProperties[index].name = property
        SourcePresent == [property \in Declarations |-> TRUE]
        SourceHandles == [property \in Declarations |-> AuthoredProperties[Position(property)].binding]
        HandleValues == {AuthoredProperties[index].binding : index \in DOMAIN AuthoredProperties}
        SourceInvariants == {property \in Declarations : AuthoredProperties[Position(property)].kind = "invariant"}
        SourceReachability == {property \in Declarations : AuthoredProperties[Position(property)].kind = "reachability"}
        ActualReferences == [property \in Declarations |-> ActualCompiledCatalog[Position(property)].ref]
        ActualAllocation == [property \in Declarations |-> ActualCompiledCatalog[Position(property)].ordinal]
        ActualFormalNames == [property \in Declarations |-> ActualCompiledCatalog[Position(property)].formal]
        AllocatedIDs == 0..(Len(AuthoredProperties) - 1)

        THEOREM ActualLayoutConstructsTheAuthoredPropertyCatalog ==
            /\ SourceCatalog \in Seq(Declarations)
            /\ SourcePresent \in [Declarations -> BOOLEAN]
            /\ SourceHandles \in [Declarations -> HandleValues]
            /\ ActualReferences \in [Declarations -> HandleValues]
            /\ ActualAllocation \in [Declarations -> AllocatedIDs]
            /\ "" \notin HandleValues
            /\ DOMAIN ActualCompiledCatalog = DOMAIN AuthoredProperties
            /\ DOMAIN ActualNativeCatalog = DOMAIN AuthoredProperties
            /\ \A left, right \in Declarations : ActualFormalNames[left] = ActualFormalNames[right] => left = right
            /\ Selection!FaithfulPropertyCatalog(SourceCatalog, Declarations, SourcePresent,
                SourceHandles, ActualReferences, ActualAllocation)
        PROOF
        <1>length. /\ Len(AuthoredProperties) \in Nat
                   /\ DOMAIN AuthoredProperties = 1..Len(AuthoredProperties)
            BY ONLY SMT DEF AuthoredProperties
        <1>function. SourceCatalog \in [1..Len(AuthoredProperties) -> Declarations]
            BY ONLY <1>length, SMT DEF SourceCatalog, Declarations
        <1>catalog. /\ SourceCatalog \in Seq(Declarations)
                    /\ Len(SourceCatalog) = Len(AuthoredProperties)
                    /\ Selection!CatalogMembers(SourceCatalog) = Declarations
            <2>seq. SourceCatalog \in Seq(Declarations)
                BY ONLY <1>length, <1>function, SequenceFacts!SeqDef, SMT
            <2>len. Len(SourceCatalog) = Len(AuthoredProperties)
                BY ONLY <1>length, <1>function, <2>seq, SequenceFacts!LenProperties, SMT DEF SourceCatalog
            <2>. QED BY ONLY <2>seq, <2>len, <1>length, SMT DEF SourceCatalog, Declarations, Selection!CatalogMembers
        <1>ordinal. \A property \in Declarations :
             /\ Position(property) \in DOMAIN AuthoredProperties
             /\ AuthoredProperties[Position(property)].name = property
             /\ Selection!CatalogOrdinal(SourceCatalog, property) = Position(property) - 1
            <2>. TAKE property \in Declarations
            <2>source. /\ Position(property) \in DOMAIN AuthoredProperties
                       /\ AuthoredProperties[Position(property)].name = property
                BY ONLY (property \in Declarations), SMT DEF Position, Declarations
            <2>choice. (CHOOSE index \in 1..Len(SourceCatalog) : SourceCatalog[index] = property) = Position(property)
                BY ONLY <1>length, <1>catalog, <2>source, SMT DEF Position, SourceCatalog
            <2>. QED BY ONLY <2>source, <2>choice DEF Selection!CatalogOrdinal
        <1>inventories. /\ DOMAIN ActualCompiledCatalog = DOMAIN AuthoredProperties
                        /\ DOMAIN ActualNativeCatalog = DOMAIN AuthoredProperties
            BY ONLY SMT DEF AuthoredProperties, ActualCompiledCatalog, ActualNativeCatalog
        <1>actual. \A index \in DOMAIN AuthoredProperties :
            /\ ActualCompiledCatalog[index].name = AuthoredProperties[index].name
            /\ ActualCompiledCatalog[index].kind = AuthoredProperties[index].kind
            /\ ActualCompiledCatalog[index].ref = AuthoredProperties[index].binding
            /\ ActualCompiledCatalog[index].ordinal = index - 1
            /\ ActualNativeCatalog[index] = ActualCompiledCatalog[index].formal
            BY ONLY SMT DEF AuthoredProperties, ActualCompiledCatalog, ActualNativeCatalog
        <1>allocation. /\ ActualAllocation = Selection!CatalogAllocation(SourceCatalog)
                        /\ ActualReferences = Selection!CatalogReferences(SourceCatalog, SourcePresent, SourceHandles)
            BY ONLY <1>catalog, <1>ordinal, <1>actual, SMT DEF ActualAllocation, ActualReferences, SourcePresent,
                SourceHandles, Selection!CatalogAllocation, Selection!CatalogReferences
        <1>types. /\ "" \notin HandleValues
                   /\ SourcePresent \in [Declarations -> BOOLEAN]
                   /\ SourceHandles \in [Declarations -> HandleValues]
                   /\ ActualReferences \in [Declarations -> HandleValues]
            BY ONLY <1>allocation, <1>catalog, <1>ordinal, SMT DEF AuthoredProperties, HandleValues, SourcePresent,
                SourceHandles, Selection!CatalogReferences
        <1>formal. \A left, right \in Declarations : ActualFormalNames[left] = ActualFormalNames[right] => left = right
            BY ONLY <1>ordinal, SMT DEF ActualFormalNames, ActualCompiledCatalog, AuthoredProperties
        <1>. QED BY ONLY <1>catalog, <1>allocation, <1>types, <1>inventories, <1>formal,
            Selection!OrderedRegistrationConstructsTheCatalogAndAllocation, SMT DEF AllocatedIDs

        LOCAL ChosenSourceProperties == Selection!SourcePropertySelection(
            Declarations, SourcePresent, SourceHandles, TRUE, AuthoredSelectedHandles)
        LOCAL ChosenLoweredIDs == Selection!LoweredPropertySelection(
            SourceCatalog, ActualReferences, ActualAllocation, TRUE, AuthoredSelectedHandles)
        LOCAL ChosenLoweredProperties == {property \in Declarations : ActualAllocation[property] \in ChosenLoweredIDs}
        SourceSelection == Selection!CheckingSignature(ChosenSourceProperties \cap SourceInvariants,
            ChosenSourceProperties \cap SourceReachability, AuthoredDeadlockChoice)
        LOCAL LoweredSelection == Selection!CheckingSignature(ChosenLoweredProperties \cap SourceInvariants,
            ChosenLoweredProperties \cap SourceReachability,
            Selection!LoweredDeadlockSelection(SourceDeadlockDefault, AuthoredDeadlockOverrides))

        NativeSelection == Selection!CheckingSignature(
            {property \in Declarations : ActualAllocation[property] \in ActualNativeChecks \cap ActualNativeInvariants},
            {property \in Declarations : ActualAllocation[property] \in ActualNativeChecks \cap ActualNativeReachability},
            ActualNativeDeadlock)

        LOCAL CFGInvariants == ActualCFGInvariantDirectives \ ActualCFGIntrinsicInvariants
        CFGSelection == Selection!CheckingSignature(
            {property \in SourceInvariants : ActualFormalNames[property] \in CFGInvariants},
            {property \in SourceReachability : ActualFormalNames[property] \in CFGInvariants},
            ActualCFGDeadlock)

        THEOREM ActualCatalogAndSelectionSupplyTheCheckingPremises ==
            /\ SourceSelection = NativeSelection
            /\ SourceSelection = CFGSelection
            /\ ActualCFGPropertyDirectives = {}
            /\ ActualRendererInvariants = {ActualFormalNames[property] : property \in CFGSelection.invariants}
            /\ ActualRendererReachability = {ActualFormalNames[property] : property \in CFGSelection.reachability}
            /\ ActualNegatedReachabilityDefinitions = ActualRendererReachability
        PROOF
        <1>inputs. /\ AuthoredSelectedHandles \subseteq HandleValues
                   /\ SourceInvariants \subseteq Declarations
                   /\ SourceReachability \subseteq Declarations
                   /\ SourceDeadlockDefault \in BOOLEAN
                   /\ AuthoredDeadlockOverrides \in Seq(BOOLEAN) /\ Len(AuthoredDeadlockOverrides) <= 1
                   /\ Selection!SourceDeadlockSelection(SourceDeadlockDefault, AuthoredDeadlockOverrides, AuthoredDeadlockChoice)
            BY ONLY SMT DEF AuthoredSelectedHandles, HandleValues, AuthoredProperties, SourceInvariants, SourceReachability,
                SourceDeadlockDefault, AuthoredDeadlockOverrides, AuthoredDeadlockChoice, Selection!SourceDeadlockSelection
        <1>selection. SourceSelection = LoweredSelection
            BY ONLY ActualLayoutConstructsTheAuthoredPropertyCatalog, <1>inputs,
                Selection!ConstructorSelectionSuppliesTheCheckingSignature, SMT
                DEF SourceSelection, LoweredSelection, ChosenLoweredProperties, ChosenLoweredIDs, ChosenSourceProperties
        <1>ids. /\ ActualCompiledChecks = ChosenLoweredIDs
                /\ ActualNativeChecks = ActualCompiledChecks
                /\ ActualCompiledDeadlock = Selection!LoweredDeadlockSelection(SourceDeadlockDefault, AuthoredDeadlockOverrides)
                /\ ActualNativeDeadlock = ActualCompiledDeadlock
            BY ONLY SMT DEF ActualCompiledChecks, ChosenLoweredIDs, Selection!LoweredPropertySelection, SourceCatalog,
                ActualReferences, ActualAllocation, Position, AuthoredProperties, Declarations, ActualCompiledCatalog,
                AuthoredSelectedHandles, ActualNativeChecks, ActualCompiledDeadlock, Selection!LoweredDeadlockSelection,
                SourceDeadlockDefault, AuthoredDeadlockOverrides, ActualNativeDeadlock
        <1>kinds. /\ {property \in Declarations : ActualAllocation[property] \in ActualNativeInvariants} = SourceInvariants
                  /\ {property \in Declarations : ActualAllocation[property] \in ActualNativeReachability} = SourceReachability
            BY ONLY SMT DEF ActualAllocation, ActualCompiledCatalog, ActualNativeInvariants, ActualNativeReachability,
                SourceInvariants, SourceReachability, AuthoredProperties, Position, Declarations
        <1>native. NativeSelection = LoweredSelection
            BY ONLY <1>ids, <1>kinds, SMT DEF NativeSelection, LoweredSelection, ChosenLoweredProperties,
                Selection!CheckingSignature
        <1>directives. /\ CFGInvariants = ActualRendererInvariants \cup ActualRendererReachability
                       /\ ActualCFGDeadlock = ActualNativeDeadlock
                       /\ ActualCFGPropertyDirectives = {}
                       /\ ActualNegatedReachabilityDefinitions = ActualRendererReachability
            BY ONLY ActualCFGBytesHaveExactlyTheCheckingDirectives, ActualTLAReachabilitySpansStartWithNegation,
                SMT DEF CFGInvariants, ActualCFGInvariantDirectives, ActualCFGIntrinsicInvariants,
                ActualRendererInvariants, ActualRendererReachability, ActualCFGDeadlock, ActualNativeDeadlock,
                ActualCFGPropertyDirectives, CFGSymbolNames, CFGCheckingRows, CFGDeadlockCode,
                ActualNegatedReachabilityDefinitions, ReachabilityNegationSpans
        <1>formal. {property \in Declarations : ActualFormalNames[property] \in CFGInvariants} = ChosenLoweredProperties
            BY ONLY <1>ids, <1>directives, SMT DEF ChosenLoweredProperties, ActualAllocation, ActualFormalNames,
                ActualCompiledCatalog, ActualCompiledChecks, Position, Declarations, AuthoredProperties,
                ActualRendererInvariants, ActualRendererReachability
        <1>cfg. CFGSelection = LoweredSelection
            BY ONLY <1>formal, <1>directives, <1>ids, <1>inputs, SMT
                DEF CFGSelection, LoweredSelection, Selection!CheckingSignature
        <1>cfgKinds. /\ ActualRendererInvariants = {ActualFormalNames[property] : property \in CFGSelection.invariants}
                     /\ ActualRendererReachability = {ActualFormalNames[property] : property \in CFGSelection.reachability}
            BY ONLY <1>directives, SMT DEF CFGSelection, Selection!CheckingSignature, SourceInvariants, SourceReachability,
                ActualFormalNames, ActualRendererInvariants, ActualRendererReachability, ActualCompiledCatalog,
                Position, AuthoredProperties, Declarations
        <1>. QED BY ONLY <1>selection, <1>native, <1>cfg, <1>directives, <1>cfgKinds, SMT

        NativeActionFailureEvents == Selection!ActionFailureEventSet(ActualNativeOrderedActionHistory)

        THEOREM ActualSelectionAndNativeHistorySupplyExactCheckingInputs ==
            /\ SourceSelection = NativeSelection
            /\ SourceSelection = CFGSelection
            /\ ActualNativeExhausted /\ ActualNativeVisitedStates > 0
            /\ \A reached, occurrence :
                   (occurrence \in Selection!ReachableCheckingFailures(reached, NativeActionFailureEvents)) <=>
                       (occurrence[1] \in reached /\ \E index \in DOMAIN ActualNativeOrderedActionHistory :
                           ActualNativeOrderedActionHistory[index] = occurrence)
        PROOF
        <1>selection. /\ SourceSelection = NativeSelection /\ SourceSelection = CFGSelection
            BY ActualCatalogAndSelectionSupplyTheCheckingPremises
        <1>run. ActualNativeExhausted /\ ActualNativeVisitedStates > 0
            BY ONLY SMT DEF ActualNativeExhausted, ActualNativeVisitedStates
        <1>events. \A reached, occurrence :
            (occurrence \in Selection!ReachableCheckingFailures(reached, NativeActionFailureEvents)) <=>
                (occurrence[1] \in reached /\ \E index \in DOMAIN ActualNativeOrderedActionHistory :
                    ActualNativeOrderedActionHistory[index] = occurrence)
            BY ONLY Selection!ReachableCheckingFailureMembershipIsAnOrderedOccurrence, SMT DEF NativeActionFailureEvents
        <1>. QED BY <1>selection, <1>run, <1>events
        """#

    private static let branchwiseSelectionProof = #"""
        BranchwiseSourceSelection == SourceSelection
        BranchwiseNativeSelection == NativeSelection
        BranchwiseCFGSelection == CFGSelection

        THEOREM ActualBranchwiseInvariantSelectionAgrees ==
            /\ BranchwiseSourceSelection = BranchwiseNativeSelection
            /\ BranchwiseSourceSelection = BranchwiseCFGSelection
            /\ \E chosen, other, omitted \in BranchwiseAuthoredInvariantNames :
                   /\ chosen # other /\ chosen # omitted /\ other # omitted
                   /\ BranchwiseSourceSelection.invariants = {chosen, other}
                   /\ omitted \notin BranchwiseSourceSelection.invariants
            /\ BranchwiseSourceSelection.reachability = {}
            /\ BranchwiseSourceSelection.deadlock = FALSE
        PROOF
        <1>common. /\ BranchwiseSourceSelection = BranchwiseNativeSelection
                   /\ BranchwiseSourceSelection = BranchwiseCFGSelection
            BY ONLY ActualCatalogAndSelectionSupplyTheCheckingPremises, SMT
                DEF BranchwiseSourceSelection, BranchwiseNativeSelection, BranchwiseCFGSelection
        <1>names. /\ \E chosen, other, omitted \in BranchwiseAuthoredInvariantNames :
                        /\ chosen # other /\ chosen # omitted /\ other # omitted
                        /\ BranchwiseNativeSelection.invariants = {chosen, other}
                        /\ omitted \notin BranchwiseNativeSelection.invariants
                  /\ BranchwiseNativeSelection.reachability = {}
                  /\ BranchwiseNativeSelection.deadlock = FALSE
            BY ONLY SMT DEF BranchwiseNativeSelection, NativeSelection, Selection!CheckingSignature, Declarations,
                Position, ActualAllocation, ActualNativeInvariants, ActualNativeReachability, ActualNativeChecks,
                ActualNativeDeadlock, ActualCompiledCatalog, AuthoredProperties, BranchwiseAuthoredInvariantNames,
                BranchwiseAuthoredInvariantRows
        <1>. QED BY ONLY <1>common, <1>names, SMT

        BranchwiseCFGEvaluationCheckEnabled ==
            /\ ActualCFGIntrinsicInvariants = {"__SwiftTLAEvaluationOK"}
            /\ "__SwiftTLAEvaluationOK" \in ActualCFGInvariantDirectives
        THEOREM ActualBranchwiseCFGContainsTheEvaluationInvariant == BranchwiseCFGEvaluationCheckEnabled
        BY ONLY ActualCFGBytesHaveExactlyTheCheckingDirectives, SMT
            DEF BranchwiseCFGEvaluationCheckEnabled, ActualCFGIntrinsicInvariants, ActualCFGInvariantDirectives,
                CFGSymbolNames, CFGCheckingRows

        BranchwiseStateIDs == 0..(Len(BranchwiseNativeSnapshots) - 1)
        BranchwiseSourceClaims ==
            [property \in BranchwiseSourceSelection.invariants |->
                [state \in BranchwiseStateIDs |-> BranchwiseAuthoredClaim(property, BranchwiseNativeSnapshots[state + 1])]]
        BranchwiseNativeClaims ==
            [property \in BranchwiseNativeSelection.invariants |->
                [state \in BranchwiseStateIDs |-> <<ActualFormalNames[property], state>> \notin BranchwiseNativeClaimFailures]]
        BranchwiseCFGClaims ==
            [property \in BranchwiseCFGSelection.invariants |->
                [state \in BranchwiseStateIDs |-> BranchwiseActualTLAClaim(property, BranchwiseNativeSnapshots[state + 1])]]

        THEOREM ActualBranchwiseClaimsAgreeOnObservedStates ==
            /\ BranchwiseSourceClaims = BranchwiseNativeClaims
            /\ BranchwiseSourceClaims = BranchwiseCFGClaims
        PROOF
        <1>selections. /\ BranchwiseSourceSelection = BranchwiseNativeSelection
                       /\ BranchwiseSourceSelection = BranchwiseCFGSelection
            BY ONLY ActualBranchwiseInvariantSelectionAgrees, SMT
        <1>names. BranchwiseNativeSelection.invariants \subseteq BranchwiseAuthoredInvariantNames
            BY ONLY SMT DEF BranchwiseNativeSelection, NativeSelection, Selection!CheckingSignature, Declarations,
                Position, ActualAllocation, ActualNativeInvariants, ActualNativeChecks, ActualCompiledCatalog,
                AuthoredProperties, BranchwiseAuthoredInvariantNames, BranchwiseAuthoredInvariantRows
        <1>observed. \A property \in BranchwiseNativeSelection.invariants, state \in BranchwiseStateIDs :
            BranchwiseAuthoredClaim(property, BranchwiseNativeSnapshots[state + 1]) =
                (<<ActualFormalNames[property], state>> \notin BranchwiseNativeClaimFailures)
            BY ONLY SMT DEF BranchwiseNativeSelection, NativeSelection, Selection!CheckingSignature, Declarations,
                Position, ActualAllocation, ActualNativeInvariants, ActualNativeChecks, ActualCompiledCatalog,
                AuthoredProperties, BranchwiseStateIDs, BranchwiseNativeSnapshots, BranchwiseAuthoredClaim,
                BranchwiseAuthoredInvariantRows, ActualFormalNames, BranchwiseNativeClaimFailures
        <1>rendered. \A property \in BranchwiseNativeSelection.invariants, state \in BranchwiseStateIDs :
            BranchwiseActualTLAClaim(property, BranchwiseNativeSnapshots[state + 1]) =
                BranchwiseAuthoredClaim(property, BranchwiseNativeSnapshots[state + 1])
            BY ONLY <1>names, BranchwiseActualPropertyDenotationsMatchAuthoredFloors, SMT
        <1>. QED BY ONLY <1>selections, <1>observed, <1>rendered, SMT
            DEF BranchwiseSourceClaims, BranchwiseNativeClaims, BranchwiseCFGClaims
        """#

    private static let selectedScalarProof = #"""
        TotalActionIntegers == TotalActionMinimum..TotalActionMaximum
        SelectedTypedActionState ==
            {snapshot \in [TotalActionIntegerFields \cup TotalActionControlFields ->
                              TotalActionIntegers \cup TotalActionControlValues] :
                /\ \A field \in TotalActionIntegerFields : snapshot[field] \in TotalActionIntegers
                /\ \A field \in TotalActionControlFields : snapshot[field] \in TotalActionControlValues}
        \* A typed scalar equality read and both literal values are defined.
        \* The pending scalar write and self-jump target actual allocated locations.
        AuthoredActionMayFail(snapshot) ==
            LET operands == AuthoredTotalActionOperands IN
            ~( /\ operands.field \in TotalActionIntegerFields
               /\ snapshot[operands.field] \in TotalActionIntegers
               /\ operands.compare \in TotalActionIntegers
               /\ operands.target \in TotalActionIntegerFields
               /\ operands.write \in TotalActionIntegers
               /\ operands.goto \in TotalActionControlValues )
        RenderedActionOperandIsDefined(snapshot, operand) ==
            CASE operand.kind = "integerRead" ->
                    /\ operand.value \in TotalActionIntegerFields
                    /\ snapshot[operand.value] \in TotalActionIntegers
              [] operand.kind = "controlRead" ->
                    /\ operand.value \in TotalActionControlFields
                    /\ snapshot[operand.value] \in TotalActionControlValues
              [] operand.kind = "integerLiteral" -> operand.value \in TotalActionIntegers
              [] operand.kind = "controlLiteral" -> operand.value \in TotalActionControlValues
              [] OTHER -> FALSE
        \* The production checker verifies complete operator bodies. The operand
        \* obligations below cover its equality, LET, write and frame fragment.
        \* Probe declarations are an additional independent report of failure sites.
        RenderedActionMayFail(snapshot) ==
            \/ ActualActionFailureDeclarations # <<>>
            \/ \E row \in DOMAIN RenderedTotalActionOperands :
                \/ row \notin DOMAIN RenderedActionDeclarationSpans
                \/ ~RenderedBytesAt(RenderedActionDeclarationSpans[row])
                \/ RenderedActionDeclarationSpans[row].name # RenderedTotalActionOperands[row].name
                \/ \E index \in DOMAIN RenderedTotalActionOperands[row].demands :
                    ~RenderedActionOperandIsDefined(snapshot, RenderedTotalActionOperands[row].demands[index])

        THEOREM ActualAuthoredAndRenderedActionsCannotFail ==
            ASSUME NEW snapshot \in SelectedTypedActionState
            PROVE /\ ~AuthoredActionMayFail(snapshot)
                  /\ ~RenderedActionMayFail(snapshot)
        PROOF
        <1>source. ~AuthoredActionMayFail(snapshot)
            BY SMT DEF AuthoredActionMayFail, AuthoredTotalActionOperands, SelectedTypedActionState,
                TotalActionIntegers, TotalActionMinimum, TotalActionMaximum, TotalActionIntegerFields,
                TotalActionControlFields, TotalActionControlValues
        <1>bytes. \A row \in DOMAIN RenderedTotalActionOperands :
            /\ row \in DOMAIN RenderedActionDeclarationSpans
            /\ RenderedBytesAt(RenderedActionDeclarationSpans[row])
            /\ RenderedActionDeclarationSpans[row].name = RenderedTotalActionOperands[row].name
            BY ONLY ActualTLAHasTheCheckedActionDeclarations, SMT
                DEF RenderedTotalActionOperands, RenderedActionDeclarationSpans
        <1>operands. \A row \in DOMAIN RenderedTotalActionOperands,
                        index \in DOMAIN RenderedTotalActionOperands[row].demands :
            RenderedActionOperandIsDefined(snapshot, RenderedTotalActionOperands[row].demands[index])
            BY SMT DEF RenderedTotalActionOperands, RenderedActionOperandIsDefined, SelectedTypedActionState,
                TotalActionIntegers, TotalActionMinimum, TotalActionMaximum, TotalActionIntegerFields,
                TotalActionControlFields, TotalActionControlValues
        <1>. QED BY ONLY <1>source, <1>bytes, <1>operands, SMT
            DEF RenderedActionMayFail, ActualActionFailureDeclarations

        \* Histories name the initial snapshot at each recorded failure occurrence.
        THEOREM ActualSelectedActionFailureHistoriesAreEmpty ==
            ASSUME NEW states, NEW labels, NEW failureRecords,
                   NEW snapshots \in [states -> SelectedTypedActionState],
                   NEW source \in Seq(states \X labels \X failureRecords),
                   NEW rendered \in Seq(states \X labels \X failureRecords),
                   \A index \in DOMAIN source : AuthoredActionMayFail(snapshots[source[index][1]]),
                   \A index \in DOMAIN rendered : RenderedActionMayFail(snapshots[rendered[index][1]])
            PROVE /\ source = <<>>
                  /\ rendered = <<>>
                  /\ ActualNativeOrderedActionHistory = <<>>
        PROOF
        <1>source. DOMAIN source = {}
            BY ActualAuthoredAndRenderedActionsCannotFail, SequenceFacts!ElementOfSeq, SMT
        <1>rendered. DOMAIN rendered = {}
            BY ActualAuthoredAndRenderedActionsCannotFail, SequenceFacts!ElementOfSeq, SMT
        <1>native. ActualNativeOrderedActionHistory = <<>>
            BY ONLY SMT DEF ActualNativeOrderedActionHistory
        <1>. QED BY <1>source, <1>rendered, <1>native, SequenceFacts!LenProperties, SMT

        \* generatedInitials, generatedEdges, generatedClaims and reached are the common
        \* graph and predicate inputs to the native and CFG-selected observations.
        \* Their correspondence to the actual backends is a separate obligation.
        THEOREM ActualSelectionSuppliesExhaustiveSelectedChecking ==
            ASSUME NEW states, NEW labels, NEW failureRecords,
                   NEW sourceInitials \in SUBSET states, NEW generatedInitials \in SUBSET states,
                   NEW sourceEdges \in SUBSET (states \X labels \X states),
                   NEW generatedEdges \in SUBSET (states \X labels \X states),
                   NEW sourceClaims \in [Declarations -> [states -> BOOLEAN]],
                   NEW generatedClaims \in [Declarations -> [states -> BOOLEAN]],
                   NEW sourceInitialFailures \in SUBSET failureRecords,
                   NEW generatedInitialFailures \in SUBSET failureRecords,
                   NEW sourceHistory \in Seq(states \X labels \X failureRecords),
                   NEW renderedHistory \in Seq(states \X labels \X failureRecords),
                   NEW snapshots \in [states -> SelectedTypedActionState],
                   \A index \in DOMAIN sourceHistory : AuthoredActionMayFail(snapshots[sourceHistory[index][1]]),
                   \A index \in DOMAIN renderedHistory : RenderedActionMayFail(snapshots[renderedHistory[index][1]]),
                   NEW reached \in SUBSET states,
                   sourceInitials = generatedInitials, sourceEdges = generatedEdges,
                   sourceInitialFailures = generatedInitialFailures,
                   \A property \in SourceSelection.invariants \cup SourceSelection.reachability,
                       state \in states : sourceClaims[property][state] = generatedClaims[property][state],
                   reached = Selection!SourceCheckingReachable(states, labels, generatedInitials, generatedEdges)
            PROVE LET source == Selection!SourceCheckingObservation(states, labels, sourceInitials, sourceEdges,
                                    SourceSelection.invariants, SourceSelection.reachability, sourceClaims,
                                    sourceInitialFailures, Selection!ActionFailureEventSet(sourceHistory),
                                    SourceSelection.deadlock)
                      generated == Selection!GeneratedCheckingObservation(labels, generatedInitials, generatedEdges, reached,
                                       NativeSelection.invariants, NativeSelection.reachability, generatedClaims,
                                       generatedInitialFailures, NativeActionFailureEvents,
                                       NativeSelection.deadlock)
                      configured == Selection!GeneratedCheckingObservation(labels, generatedInitials, generatedEdges, reached,
                                        CFGSelection.invariants, CFGSelection.reachability, generatedClaims,
                                        generatedInitialFailures, Selection!ActionFailureEventSet(renderedHistory),
                                        CFGSelection.deadlock)
                  IN /\ source = generated
                     /\ source = configured
                     /\ sourceHistory = ActualNativeOrderedActionHistory
                     /\ renderedHistory = ActualNativeOrderedActionHistory
                     /\ \A occurrence \in states \X labels \X failureRecords :
                            (occurrence \in generated.actionFailures) <=>
                                (occurrence[1] \in reached /\ \E index \in DOMAIN ActualNativeOrderedActionHistory :
                                    ActualNativeOrderedActionHistory[index] = occurrence)
        PROOF
        <1>. DEFINE source == Selection!SourceCheckingObservation(states, labels, sourceInitials, sourceEdges,
                                 SourceSelection.invariants, SourceSelection.reachability, sourceClaims,
                                 sourceInitialFailures, Selection!ActionFailureEventSet(sourceHistory),
                                 SourceSelection.deadlock)
                    generated == Selection!GeneratedCheckingObservation(labels, generatedInitials, generatedEdges, reached,
                                    NativeSelection.invariants, NativeSelection.reachability, generatedClaims,
                                    generatedInitialFailures, NativeActionFailureEvents, NativeSelection.deadlock)
                    configured == Selection!GeneratedCheckingObservation(labels, generatedInitials, generatedEdges, reached,
                                     CFGSelection.invariants, CFGSelection.reachability, generatedClaims,
                                     generatedInitialFailures, Selection!ActionFailureEventSet(renderedHistory), CFGSelection.deadlock)
        <1>total. /\ sourceHistory = ActualNativeOrderedActionHistory
                   /\ renderedHistory = ActualNativeOrderedActionHistory
            BY ActualSelectedActionFailureHistoriesAreEmpty, SMT
        <1>histories. /\ ActualNativeOrderedActionHistory \in Seq(states \X labels \X failureRecords)
                      /\ DOMAIN sourceHistory = DOMAIN ActualNativeOrderedActionHistory
                      /\ \A index \in DOMAIN sourceHistory : sourceHistory[index] = ActualNativeOrderedActionHistory[index]
            BY ONLY (sourceHistory \in Seq(states \X labels \X failureRecords)),
                <1>total, SMT
        <1>signature. /\ SourceSelection = NativeSelection
                      /\ NativeSelection = CFGSelection
                      /\ SourceSelection.invariants \subseteq Declarations
                      /\ SourceSelection.reachability \subseteq Declarations
                      /\ SourceSelection.deadlock \in BOOLEAN
            BY ONLY ActualSelectionAndNativeHistorySupplyExactCheckingInputs, SMT
                DEF SourceSelection, Selection!CheckingSignature, ChosenSourceProperties, SourceInvariants,
                    SourceReachability, AuthoredDeadlockChoice
        <1>native. source = generated
            BY <1>histories, <1>signature, Selection!ExhaustiveSelectedCheckingWithOrderedActionFailures, SMT
                DEF source, generated, NativeActionFailureEvents
        <1>cfg. generated = configured
            BY ONLY <1>total, <1>signature, SMT DEF generated, configured, NativeActionFailureEvents
        <1>occurrences. \A occurrence \in states \X labels \X failureRecords :
            (occurrence \in generated.actionFailures) <=>
                (occurrence[1] \in reached /\ \E index \in DOMAIN ActualNativeOrderedActionHistory :
                    ActualNativeOrderedActionHistory[index] = occurrence)
            BY ONLY ActualSelectionAndNativeHistorySupplyExactCheckingInputs, SMT
                DEF generated, Selection!GeneratedCheckingObservation
        <1>. QED BY ONLY <1>total, <1>native, <1>cfg, <1>occurrences, SMT DEF source, generated, configured
        """#
}
