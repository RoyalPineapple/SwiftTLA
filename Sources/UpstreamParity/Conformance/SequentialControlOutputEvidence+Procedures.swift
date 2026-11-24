import Foundation
import SwiftTLA

extension SequentialControlOutputEvidence {
    /// Bind control, supported body writes, and skipped assertions of a registered procedure While.
    package static func procedureLoopProof(
        source: SequentialControlEvidence.ProcedureLoopSource,
        program: CompiledProgram, rendered: RenderedSpecification
    ) throws -> (name: String, bytes: Data)? {
        let module = rendered.tlaBundle.root
        guard case .compiled(let identity, _, _) = rendered.tlaBundle.provenance,
              identity == program.identity, rendered.tlaBundle.imports.isEmpty,
              module.name == program.moduleName, !module.tla.contains("AuthoredProcedureLoop"),
              let cfg = module.cfg,
              let pc = program.layout.variables.first(where: { $0.declaration.origin == .programCounter })
        else { return nil }
        let rows = rendered.actions.filter { $0.sourceName.utf8.elementsEqual(source.action.utf8) }
        guard let action = rows.first?.emittedBaseName, !rows.isEmpty,
              rows.allSatisfy({ $0.emittedBaseName == action && $0.arguments.count == 1 }),
              Set(rows.map(\.renderedName)).count == rows.count else { return nil }
        let labels = try source.labels.compactMap { name -> TLAValue? in
            let matches = program.layout.controlLocations.filter {
                $0.owner == source.owner && $0.sourceName.utf8.elementsEqual(name.utf8)
            }
            guard matches.count == 1, let label = matches.first else { return nil }
            return try CompiledValue.controlLocation(label.id).rendered(using: program.layout)
        }
        guard labels.count == source.labels.count else { return nil }

        func variable(_ root: String) -> CompiledVariableLayout? {
            let matches = program.layout.variables.filter { $0.declaration.name.utf8.elementsEqual(root.utf8) }
            return matches.count == 1 ? matches.first : nil
        }
        var tables: Set<String> = [pc.formalName]
        var readDomains: [String: String] = [:]
        guard let condition = procedureTerm(source.condition, variable: { root in
            guard let layout = variable(root), let storage = program.variableTypes[layout.id] else { return nil }
            let name = layout.formalName
            let read: String
            let type: CompiledValueType
            if source.localRoots.contains(root) {
                guard case .dictionary(_, let element) = storage else { return nil }
                tables.insert(name)
                read = "\(name)[worker]"
                type = element
            } else {
                read = name
                type = storage
            }
            switch type {
            case .int: readDomains[read] = "Int"
            case .bool: readDomains[read] = "BOOLEAN"
            default: return nil
            }
            return read
        }),
              let cfgInput = try procedureConfiguration(cfg, rendered: rendered) else { return nil }
        let assertions = cfgInput.invariants.filter { $0.hasPrefix("__pcal_assert_") }
        guard !source.ownsConfiguredAssertions || !assertions.isEmpty else { return nil }
        let frame = program.layout.variables.filter { $0.id != pc.id }.map(\.formalName)
        let assumed = (tables.sorted().map { #"worker \in DOMAIN \#($0)"# }
                       + readDomains.sorted(by: { $0.key < $1.key }).map { #"\#($0.key) \in \#($0.value)"# })
            .joined(separator: #" /\ "#)
        let workerValues = rows.map { $0.arguments[0].description }
        let pcName = pc.formalName
        let trueArm = source.fallsThrough ? #"""
            /\ ((\#(action)(worker) /\ AuthoredProcedureLoopGuard(worker)) =>
                \#(pcName)' = [\#(pcName) EXCEPT ![worker] = AuthoredProcedureLoopEntry])
        """# : ""
        let body = procedureLoopBody(source, counter: pcName, frame: frame, action: action,
                                     formalName: { variable($0)?.formalName })
        guard source.body == nil || body != nil else { return nil }
        let bodyResult = body == nil ? "" : #"""
            /\ (\A worker : AuthoredProcedureLoopBodyInput(worker) => AuthoredProcedureLoopBodyWritesAgree(worker))
        """#
        let bodyFact = body == nil ? "" : ", ActualProcedureWhilePublishesTheAuthoredWrites"
        let assertionScope = workerValues.map { #"AuthoredProcedureLoopSkipped(\#($0))"# }.joined(separator: #" /\ "#)
        let assertionSource: String
        let assertionResult: String
        let assertionFact: String
        if source.ownsConfiguredAssertions && !assertions.isEmpty {
            let selected = assertions.joined(separator: #" /\ "#)
            assertionSource = #"""
            LOCAL AuthoredProcedureLoopSkipped(worker) ==
                /\ AuthoredProcedureLoopInput(worker)
                /\ ~(\#(pcName)[worker] = AuthoredProcedureLoopEntry /\ AuthoredProcedureLoopGuard(worker))
            AuthoredProcedureLoopSkipsConfiguredAssertions ==
                (\#(assertionScope)) => (\#(selected))

            THEOREM ActualUnreachedProcedureAssertionsHold ==
                AuthoredProcedureLoopSkipsConfiguredAssertions
                BY ONLY SMT DEF AuthoredProcedureLoopSkipsConfiguredAssertions, AuthoredProcedureLoopSkipped,
                    AuthoredProcedureLoopInput, AuthoredProcedureLoopGuard, AuthoredProcedureLoopEntry,
                    AuthoredProcedureLoopEntries, \#(assertions.joined(separator: ", "))
            """#
            assertionResult = #"    /\ AuthoredProcedureLoopSkipsConfiguredAssertions"#
            assertionFact = ", ActualUnreachedProcedureAssertionsHold"
        } else {
            assertionSource = ""
            assertionResult = ""
            assertionFact = ""
        }
        let selection = procedureNext(rows, predicate: "AuthoredProcedureLoopInNext",
                                      theorem: "ActualNextIncludesTheSelectedProcedureLoop")
        let configuration = procedureCFG(cfgInput.expected, prefix: "ProcedureLoop", theorem: "ActualProcedureLoopConfigurationIsSelected")
        let slot = source.slot + 1
        let name = "SwiftTLA" + module.name + "ConfiguredProcedureLoopProof"
        let proof = #"""
        ---- MODULE \#(name) ----
        EXTENDS \#(module.name), TLAPS, \#(configuration.blocks)

        LOCAL Routes == INSTANCE ActionOutcomeInterface
            WITH UpdateValues <- {}, FailureValues <- {}, NoFailure <- <<>>
        \* Registered procedure \#(source.procedure), SwiftSyntax byte offset \#(source.sourceOffset).
        AuthoredProcedureLoopEntries == \#(TLAValue.tuple(labels))
        AuthoredProcedureLoopEntry == AuthoredProcedureLoopEntries[\#(slot)]
        AuthoredProcedureLoopFollowing == Routes!FollowingSequentialEntry(AuthoredProcedureLoopEntries, \#(slot), <<>>)
        AuthoredProcedureLoopInput(worker) == \#(assumed)
        AuthoredProcedureLoopGuard(worker) == \#(condition)
        AuthoredProcedureLoopFalseArm(worker) ==
            /\ \#(pcName)[worker] = AuthoredProcedureLoopEntry
            /\ \#(pcName)' = [\#(pcName) EXCEPT ![worker] = AuthoredProcedureLoopFollowing]
            /\ UNCHANGED <<\#(frame.joined(separator: ", "))>>
        AuthoredProcedureLoopControl(worker) ==
            /\ (~AuthoredProcedureLoopGuard(worker) =>
                (\#(action)(worker) <=> AuthoredProcedureLoopFalseArm(worker)))
        \#(trueArm)

        THEOREM ActualProcedureWhileUsesTheAuthoredControl ==
            ASSUME NEW worker, AuthoredProcedureLoopInput(worker)
            PROVE AuthoredProcedureLoopControl(worker)
        PROOF
        <1>domain. DOMAIN AuthoredProcedureLoopEntries = 1..\#(labels.count)
            BY ONLY IsaM("simp") DEF AuthoredProcedureLoopEntries
        <1>next. AuthoredProcedureLoopFollowing = AuthoredProcedureLoopEntries[\#(slot + 1)]
            BY ONLY <1>domain, Routes!FollowingSequentialEntryUsesTheRegisteredOrder, SMT DEF AuthoredProcedureLoopFollowing
        <1>. QED BY ONLY <1>next, AuthoredProcedureLoopInput(worker), SMT
            DEF \#(action), AuthoredProcedureLoopControl, AuthoredProcedureLoopFalseArm,
                AuthoredProcedureLoopInput, AuthoredProcedureLoopEntry, AuthoredProcedureLoopEntries, AuthoredProcedureLoopGuard

        \#(body ?? "")

        \#(assertionSource)

        \#(selection)

        \#(configuration.proof)

        THEOREM ConfiguredProcedureControlUsesTheAuthoredPaths ==
            /\ ProcedureLoopActualCFG = ProcedureLoopExpectedCFG
            /\ AuthoredProcedureLoopInNext
            /\ (\A worker : AuthoredProcedureLoopInput(worker) => AuthoredProcedureLoopControl(worker))
        \#(bodyResult)
        \#(assertionResult)
            BY ONLY ActualProcedureLoopConfigurationIsSelected, ActualNextIncludesTheSelectedProcedureLoop,
                ActualProcedureWhileUsesTheAuthoredControl\#(bodyFact)\#(assertionFact), Zenon

        ====

        """#
        return (name, Data(proof.utf8))
    }

    private static func procedureLoopBody(
        _ source: SequentialControlEvidence.ProcedureLoopSource, counter: String, frame: [String],
        action: String, formalName: (String) -> String?
    ) -> String? {
        guard let body = source.body, let trace = body.canonicalTrace(sourceWrites: true) else { return nil }
        var touched: Set<String> = []
        for case .write(let target, let value) in body.observations {
            touched.insert(target)
            touched.formUnion(value.freeVariableNames)
        }
        var names: [String: String] = [:]
        for root in touched {
            guard let name = formalName(root), frame.contains(name) else { return nil }
            names[root] = name
        }
        let definedWorkers = source.localRoots.intersection(touched).compactMap { names[$0] }.sorted()
        let bodyInput = (["AuthoredProcedureLoopInput(worker)"] + definedWorkers.map { #"worker \in DOMAIN \#($0)"# })
            .joined(separator: #" /\ "#)
        var targets: Set<String> = []
        var writes: [String] = []
        for case .write(let root, let value) in trace.observations {
            guard let target = names[root], targets.insert(target).inserted,
                  let rhs = procedureTerm(value, variable: { read in
                      guard let name = names[read] else { return nil }
                      return source.localRoots.contains(read) ? "\(name)[worker]" : name
                  }) else { return nil }
            let update = source.localRoots.contains(root) ? "[\(target) EXCEPT ![worker] = \(rhs)]" : rhs
            writes.append(#"/\ \#(target)' = \#(update)"#)
        }
        let unchanged = frame.filter { !targets.contains($0) }.joined(separator: ", ")
        let updates = (writes + [#"/\ UNCHANGED <<\#(unchanged)>>"#]).joined(separator: "\n    ")
        return #"""
        AuthoredProcedureLoopBodyInput(worker) == \#(bodyInput)
        AuthoredProcedureLoopTrueArm(worker) ==
            /\ \#(counter)[worker] = AuthoredProcedureLoopEntry
            /\ AuthoredProcedureLoopGuard(worker)
            /\ \#(counter)' = [\#(counter) EXCEPT ![worker] = AuthoredProcedureLoopEntry]
            \#(updates)
        AuthoredProcedureLoopBodyWritesAgree(worker) ==
            ((\#(action)(worker) /\ AuthoredProcedureLoopGuard(worker)) <=> AuthoredProcedureLoopTrueArm(worker))

        THEOREM ActualProcedureWhilePublishesTheAuthoredWrites ==
            ASSUME NEW worker, AuthoredProcedureLoopBodyInput(worker)
            PROVE AuthoredProcedureLoopBodyWritesAgree(worker)
            BY ONLY AuthoredProcedureLoopBodyInput(worker), SMT
                DEF \#(action), AuthoredProcedureLoopBodyWritesAgree, AuthoredProcedureLoopTrueArm,
                    AuthoredProcedureLoopGuard, AuthoredProcedureLoopEntry, AuthoredProcedureLoopEntries,
                    AuthoredProcedureLoopBodyInput, AuthoredProcedureLoopInput
        """#
    }

    private static func procedureTerm(
        _ expression: StateExpr, variable: (String) -> String?, workerLookup: ((String) -> String?)? = nil
    ) -> String? {
        func render(_ expression: StateExpr) -> String? {
            procedureTerm(expression, variable: variable, workerLookup: workerLookup)
        }
        func binary(_ left: StateExpr, _ op: String, _ right: StateExpr) -> String? {
            guard let a = render(left), let b = render(right) else { return nil }
            return "(\(a) \(op) \(b))"
        }
        switch expression {
        case .variable(let root): return variable(root)
        case .value(.int(let value)): return TLAValue.int(value).description
        case .value(.bool(let value)): return value ? "TRUE" : "FALSE"
        case .currentProcess: return workerLookup == nil ? nil : "worker"
        case .functionApply(.variable(let root), .currentProcess): return workerLookup?(root)
        case .equal(let a, let b): return binary(a, "=", b)
        case .greaterThan(let a, let b): return binary(a, ">", b)
        case .lessThan(let a, let b): return binary(a, "<", b)
        case .and(let a, let b):
            guard let left = render(a), let right = render(b) else { return nil }
            return "(IF \(left) THEN \(right) ELSE FALSE)"
        default: return nil
        }
    }

    private static func procedureConfiguration(
        _ cfg: String, rendered: RenderedSpecification
    ) throws -> (invariants: [String], expected: String)? {
        guard rendered.behavior == .specification, rendered.checksDeadlock,
              rendered.reachabilityNames.isEmpty else { return nil }
        let selection = try rendered.checkSelection(checking: rendered.checkNames, checkDeadlock: true)
        let invariants = selection.intrinsicInvariantNames + selection.tlcInvariantNames
        guard selection.tlcPropertyNames.isEmpty,
              Set(invariants) == rendered.invariantNames.union(rendered.intrinsicInvariantNames),
              Set(invariants).count == invariants.count else { return nil }
        let expectedCFG = (["SPECIFICATION Spec", "CHECK_DEADLOCK TRUE"]
            + invariants.map { "INVARIANT \($0)" }).joined(separator: "\n") + "\n"
        guard cfg.utf8.elementsEqual(expectedCFG.utf8) else { return nil }
        return (invariants, expectedCFG)
    }

    private static func procedureNext(_ rows: [RenderedAction], predicate: String, theorem: String) -> String {
        let members = rows.map { #"/\ (\#($0.emittedInvocationName) => Next)"# }.joined(separator: "\n    ")
        let definitions = (["Next"] + rows.compactMap {
            $0.renderedName == $0.emittedBaseName ? nil : $0.renderedName
        }).joined(separator: ", ")
        return #"""
        \#(predicate) ==
            \#(members)
        THEOREM \#(theorem) ==
            \#(predicate)
            BY ONLY PTL DEF \#(predicate), \#(definitions)
        """#
    }

    private static func procedureCFG(
        _ expectedCFG: String, prefix: String, theorem: String
    ) -> (blocks: String, proof: String) {
        let cfgBytes = Array(expectedCFG.utf8)
        let cfgPages = stride(from: 0, to: cfgBytes.count, by: 16).enumerated().map { index, offset in
            (number: index + 1, offset: offset, end: min(offset + 16, cfgBytes.count))
        }
        let pages = cfgPages.map { "CallerInputPage\($0.number)" }.joined(separator: " ")
        let blocks = Set(cfgPages.map { ($0.number - 1) / 64 + 1 }).sorted()
            .map { "CallerInputPageBlock\($0)" }.joined(separator: ", ")
        let pageDefinitions = cfgPages.map { page in
            let bytes = TLAValue.tuple(cfgBytes[page.offset..<page.end].map { .int(Int($0)) })
            return "LOCAL \(prefix)CFGPage\(page.number)(j) == \(bytes)[j]"
        }.joined(separator: "\n")
        let pageSelection = cfgPages.map { page in
            #"i \in \#(page.offset + 1)..\#(page.end) -> \#(prefix)CFGPage\#(page.number)(i - \#(page.offset))"#
        }.joined(separator: "\n        [] ")
        let pageProofs = cfgPages.map { page in
            let start = page.offset + 1
            let expected = "\(prefix)CFGPage\(page.number)"
            let input = "CallerInputPageBlock\((page.number - 1) / 64 + 1)AtFileOffsets"
            return #"""
            <1>page\#(page.number). \A i \in \#(start)..\#(page.end) :
                \#(prefix)ActualCFG[i] = \#(prefix)ExpectedCFG[i]
                <2>input. \A j \in 1..\#(page.end - page.offset) :
                    CallerInputByte[\#(page.offset) + j - 1] = \#(expected)(j)
                    BY ONLY \#(input) DEF \#(expected)
                <2>expected. \A i \in \#(start)..\#(page.end) :
                    \#(prefix)ExpectedCFG[i] = \#(expected)(i - \#(page.offset))
                    BY ONLY SMT DEF \#(prefix)ExpectedCFG
                <2>. QED BY ONLY <2>input, <2>expected, SMT DEF \#(prefix)ActualCFG, CallerInputSize
            """#
        }.joined(separator: "\n")
        let pageFacts = cfgPages.map { "<1>page\($0.number)" }.joined(separator: ", ")
        let proof = #"""
        \* \#(pages)
        \#(prefix)ActualCFG == [i \in 1..CallerInputSize |-> CallerInputByte[i - 1]]
        \#(pageDefinitions)
        \#(prefix)ExpectedCFG ==
            [i \in 1..\#(cfgBytes.count) |->
                CASE \#(pageSelection)
                  [] OTHER -> 0]
        THEOREM \#(theorem) ==
            \#(prefix)ActualCFG = \#(prefix)ExpectedCFG
        PROOF
        \#(pageProofs)
        <1>entries. \A i \in 1..\#(cfgBytes.count) : \#(prefix)ActualCFG[i] = \#(prefix)ExpectedCFG[i]
            BY ONLY \#(pageFacts), SMT
        <1>actual. \#(prefix)ActualCFG = [i \in 1..\#(cfgBytes.count) |-> \#(prefix)ActualCFG[i]]
            BY ONLY SMT DEF \#(prefix)ActualCFG, CallerInputSize
        <1>expected. \#(prefix)ExpectedCFG = [i \in 1..\#(cfgBytes.count) |-> \#(prefix)ExpectedCFG[i]]
            BY ONLY SMT DEF \#(prefix)ExpectedCFG
        <1>functions. [i \in 1..\#(cfgBytes.count) |-> \#(prefix)ActualCFG[i]]
                    = [i \in 1..\#(cfgBytes.count) |-> \#(prefix)ExpectedCFG[i]]
            BY ONLY <1>entries, SMT
        <1>. QED BY ONLY <1>actual, <1>expected, <1>functions, Zenon
        """#
        return (blocks, proof)
    }
}

extension SequentialControlOutputEvidence {
    /// Bind both arms of a While with a bare Call and project the callee’s successful return.
    package static func callWhileProof(
        specification: TLASpec
    ) throws -> (compilation: CompiledSpecification, output: RenderedSpecification, name: String, bytes: Data)? {
        guard specification.sourceAlgorithms.count == 1,
              let source = specification.sourceAlgorithms.first?.model else { return nil }
        let processes = source.components.compactMap { component -> AlgorithmProcessModel? in
            guard case .process(let process) = component else { return nil }
            return process
        }
        let procedures = source.components.compactMap { component -> AlgorithmProcedureModel? in
            guard case .procedure(let procedure) = component else { return nil }
            return procedure
        }
        let sequential = source.components.compactMap { component -> AlgorithmStepModel? in
            guard case .step(let step) = component else { return nil }
            return step
        }
        guard processes.count <= 1, processes.isEmpty || sequential.isEmpty else { return nil }
        let process = processes.first
        let steps = process?.steps ?? sequential
        let owner: ControlOwner = process.map {
            .process(algorithm: source.name, ordinal: 0, typeName: $0.typeName)
        } ?? .sequential(algorithm: source.name)
        let calls = steps.enumerated().compactMap { index, step -> (Int, StateExpr, String, [StateExpr])? in
            guard let condition = step.loopCondition, steps.indices.contains(index + 1),
                  step.statements.count == 1,
                  case .call(let target, let arguments) = step.statements[0]
            else { return nil }
            return (index, condition, target, arguments)
        }
        guard calls.count == 1, let (index, condition, target, arguments) = calls.first,
              let procedure = procedures.first(where: { $0.name == target }),
              let entry = procedure.steps.first?.label.name,
              arguments.count == procedure.parameters.count else { return nil }
        let returns = procedure.steps.filter { step in
            step.loopCondition == nil && step.statements.last == .return
                && step.statements.dropLast().allSatisfy { statement in
                    switch statement {
                    case .set, .skip: return true
                    default: return false
                    }
                }
        }
        guard returns.count == 1, let returnLabel = returns.first?.label.name else { return nil }

        let compilation = try specification.compile()
        let layout = compilation.layout
        guard let pc = layout.variables.first(where: { $0.declaration.origin == .programCounter })?.formalName,
              let stack = layout.variables.first(where: { $0.declaration.origin == .procedureStack })?.formalName
        else { return nil }
        let scoped = process != nil
        func location(_ owner: ControlOwner, _ label: String) -> TLAValue? {
            layout.controlLocations.first {
                $0.owner == owner && $0.sourceName.utf8.elementsEqual(label.utf8)
            }.map { .string($0.formalName) }
        }
        let labels = steps.compactMap { location(owner, $0.label.name) }
        guard labels.count == steps.count,
              let destination = location(.procedure(algorithm: source.name, name: target), entry)
        else { return nil }

        func formalName(_ root: String, origin: VariableOrigin) -> String? {
            let matches = layout.variables.filter {
                $0.declaration.origin == origin && $0.declaration.name.utf8.elementsEqual(root.utf8)
            }
            return matches.count == 1 ? matches.first?.formalName : nil
        }
        func slotName(_ root: String) -> String? { formalName(root, origin: .compiler) }
        let frameKeys = procedures.flatMap { $0.parameters.map(\.root) + $0.locals.map(\.root) }
        let saved = frameKeys.compactMap { key in slotName(key).map { (key, $0) } }
        let counterField = CompilerControlSymbol.programCounter.rawValue
        let procedureField = CompilerControlSymbol.procedure.rawValue
        guard saved.count == frameKeys.count, Set(frameKeys).count == frameKeys.count,
              !frameKeys.contains(counterField), !frameKeys.contains(procedureField),
              frameKeys.allSatisfy({ $0.range(of: #"^[A-Za-z][A-Za-z0-9_]*$"#, options: .regularExpression) != nil })
        else { return nil }
        let shared = source.components.compactMap { component -> AlgorithmStateModel? in
            guard case .shared(let state) = component else { return nil }
            return state
        }
        let locals = process?.components.compactMap { component -> AlgorithmStateModel? in
            guard case .local(let state) = component else { return nil }
            return state
        } ?? []
        func atWorker(_ name: String) -> String { scoped ? "\(name)[worker]" : name }
        func assign(_ name: String, _ value: String) -> String {
            scoped ? "\(name)' = [\(name) EXCEPT ![worker] = \(value)]" : "\(name)' = \(value)"
        }
        var indexedReads = Set([pc, stack] + saved.map { $0.1 })
        func indexed(_ name: String) -> String {
            indexedReads.insert(name)
            return atWorker(name)
        }
        func term(_ expression: StateExpr) -> String? {
            procedureTerm(expression, variable: { root in
                if let local = locals.first(where: { $0.root.utf8.elementsEqual(root.utf8) }) {
                    return formalName(root, origin: local.exposed ? .source : .compiler).map(indexed)
                }
                guard shared.contains(where: { $0.root.utf8.elementsEqual(root.utf8) }) else { return nil }
                return formalName(root, origin: .source)
            }, workerLookup: !scoped ? nil : { root in
                guard shared.contains(where: { $0.root.utf8.elementsEqual(root.utf8) }) else { return nil }
                return formalName(root, origin: .source).map(indexed)
            })
        }
        guard let guardValue = term(condition) else { return nil }
        let parameters = zip(procedure.parameters, arguments).compactMap { parameter, argument -> String? in
            guard let name = slotName(parameter.root), let value = term(argument) else { return nil }
            return assign(name, value)
        }
        let initialized = procedure.locals.compactMap { local -> String? in
            guard let name = slotName(local.root), case .value(let value) = local.initialization,
                  let expression = term(.value(value)) else { return nil }
            return assign(name, expression)
        }
        guard parameters.count == arguments.count, initialized.count == procedure.locals.count else { return nil }

        let rendered = try compilation.render()
        let module = rendered.tlaBundle.root
        guard rendered.tlaBundle.imports.isEmpty, module.name == source.name,
              !module.tla.contains("AuthoredCallWhile"), let cfg = module.cfg,
              let cfgInput = try procedureConfiguration(cfg, rendered: rendered) else { return nil }
        let workers: [[TLAValue]]
        if let process {
            guard case .setLiteral(let domain) = process.domain, !domain.isEmpty else { return nil }
            workers = domain.compactMap {
                guard case .value(let value) = $0 else { return nil }
                return [value]
            }
            guard workers.count == domain.count, Set(workers).count == workers.count else { return nil }
        } else {
            workers = [[]]
        }
        func actions(_ label: String) -> [RenderedAction]? {
            let rows = rendered.actions.filter { $0.sourceName.utf8.elementsEqual(label.utf8) }
            guard let base = rows.first?.emittedBaseName, rows.count == workers.count,
                  rows.allSatisfy({ $0.emittedBaseName == base }),
                  Set(rows.map(\.arguments)) == Set(workers)
            else { return nil }
            return rows
        }
        guard let callRows = actions(steps[index].label.name), let call = callRows.first?.emittedBaseName,
              let returnRows = actions("procedure.\(target).\(returnLabel)"),
              let returning = returnRows.first?.emittedBaseName else { return nil }

        let suffix = scoped ? "(worker)" : ""
        let quantified = scoped ? #"\A worker : "# : ""
        let input = scoped ? indexedReads.sorted().map { #"worker \in DOMAIN \#($0)"# }.joined(separator: #" /\ "#) : "TRUE"
        let stackBefore = atWorker(stack)
        let frame = ["\(procedureField) |-> \(TLAValue.string(target))", "\(counterField) |-> AuthoredCallWhileEntry"]
            + saved.map { "\($0.0) |-> \(atWorker($0.1))" }
        let restored = saved.map { key, variable in assign(variable, "(Head(\(stackBefore))).\(key)") }
        func unchanged(except updates: Set<String>) -> String {
            let names = layout.variables.map(\.formalName).filter { !updates.contains($0) }
            return names.isEmpty ? "TRUE" : "UNCHANGED <<\(names.joined(separator: ", "))>>"
        }
        let callTargets = (procedure.parameters.map(\.root) + procedure.locals.map(\.root)).compactMap(slotName)
        let callUpdates = parameters + initialized + [
            assign(pc, destination.description),
            assign(stack, "<<AuthoredCallWhileFrame\(suffix)>> \\o \(stackBefore)"),
            unchanged(except: Set(callTargets + [pc, stack])),
        ]
        let returnUpdates = [
            "Len(\(stackBefore)) > 0",
            assign(pc, "(Head(\(stackBefore))).\(counterField)"),
            assign(stack, "Tail(\(stackBefore))"),
        ] + restored
        func clauses(_ values: [String]) -> String { values.map { #"/\ \#($0)"# }.joined(separator: "\n    ") }
        let selection = procedureNext(callRows + returnRows, predicate: "AuthoredCallWhileInNext",
                                      theorem: "ActualNextIncludesTheCallAndReturn")
        let configuration = procedureCFG(cfgInput.expected, prefix: "CallWhile", theorem: "ActualCallWhileConfigurationIsSelected")
        let slot = index + 1
        let name = "SwiftTLA" + module.name + "ConfiguredCallWhileProof"
        let proof = #"""
        ---- MODULE \#(name) ----
        EXTENDS \#(module.name), TLAPS, \#(configuration.blocks)

        LOCAL Routes == INSTANCE ActionOutcomeInterface
            WITH UpdateValues <- {}, FailureValues <- {}, NoFailure <- <<>>
        AuthoredCallWhileEntries == \#(TLAValue.tuple(labels))
        AuthoredCallWhileEntry == AuthoredCallWhileEntries[\#(slot)]
        AuthoredCallWhileExit == Routes!FollowingSequentialEntry(AuthoredCallWhileEntries, \#(slot), <<>>)
        AuthoredCallWhileInput\#(suffix) == \#(input)
        AuthoredCallWhileGuard\#(suffix) == \#(guardValue)
        AuthoredCallWhileFrame\#(suffix) == [\#(frame.joined(separator: ", "))]
        AuthoredCallWhilePush\#(suffix) ==
            /\ \#(atWorker(pc)) = AuthoredCallWhileEntry
            \#(clauses(callUpdates))
        AuthoredCallWhileSkip\#(suffix) ==
            /\ \#(atWorker(pc)) = AuthoredCallWhileEntry
            /\ \#(assign(pc, "AuthoredCallWhileExit"))
            /\ \#(unchanged(except: [pc]))
        AuthoredCallWhilePop\#(suffix) ==
            \#(clauses(returnUpdates))

        AuthoredCallWhileSavesContinuation ==
            \#(quantified)((AuthoredCallWhileInput\#(suffix) /\ AuthoredCallWhileGuard\#(suffix))
                => (\#(call)\#(suffix) <=> AuthoredCallWhilePush\#(suffix)))
        AuthoredCallWhileAdvancesOnFalse ==
            \#(quantified)((AuthoredCallWhileInput\#(suffix) /\ ~AuthoredCallWhileGuard\#(suffix))
                => (\#(call)\#(suffix) <=> AuthoredCallWhileSkip\#(suffix)))
        AuthoredCallWhileRestoresContinuation ==
            \#(quantified)((AuthoredCallWhileInput\#(suffix) /\ \#(returning)\#(suffix))
                => AuthoredCallWhilePop\#(suffix))

        THEOREM ActualCallWhileSavesTheAuthoredContinuation ==
            AuthoredCallWhileSavesContinuation
            BY ONLY SMT DEF AuthoredCallWhileSavesContinuation, AuthoredCallWhileInput, AuthoredCallWhileGuard,
                AuthoredCallWhilePush, AuthoredCallWhileFrame, AuthoredCallWhileEntry, AuthoredCallWhileEntries, \#(call)

        THEOREM ActualFalseCallWhileTakesTheAuthoredNextLabel ==
            AuthoredCallWhileAdvancesOnFalse
        PROOF
        <1>domain. DOMAIN AuthoredCallWhileEntries = 1..\#(labels.count)
            BY ONLY IsaM("simp") DEF AuthoredCallWhileEntries
        <1>next. AuthoredCallWhileExit = AuthoredCallWhileEntries[\#(slot + 1)]
            BY ONLY <1>domain, Routes!FollowingSequentialEntryUsesTheRegisteredOrder, SMT DEF AuthoredCallWhileExit
        <1>. QED BY ONLY <1>next, SMT DEF AuthoredCallWhileAdvancesOnFalse, AuthoredCallWhileInput,
            AuthoredCallWhileGuard, AuthoredCallWhileSkip, AuthoredCallWhileEntry, AuthoredCallWhileEntries, \#(call)

        THEOREM ActualCallWhileReturnRestoresTheSavedContinuation ==
            AuthoredCallWhileRestoresContinuation
            BY ONLY SMT DEF AuthoredCallWhileRestoresContinuation, AuthoredCallWhileInput,
                AuthoredCallWhilePop, \#(returning)

        \#(selection)

        \#(configuration.proof)

        THEOREM ConfiguredCallWhileUsesTheAuthoredContinuations ==
            /\ CallWhileActualCFG = CallWhileExpectedCFG
            /\ AuthoredCallWhileInNext
            /\ AuthoredCallWhileSavesContinuation
            /\ AuthoredCallWhileAdvancesOnFalse
            /\ AuthoredCallWhileRestoresContinuation
            BY ONLY ActualCallWhileConfigurationIsSelected, ActualNextIncludesTheCallAndReturn,
                ActualCallWhileSavesTheAuthoredContinuation, ActualFalseCallWhileTakesTheAuthoredNextLabel,
                ActualCallWhileReturnRestoresTheSavedContinuation, PTL

        ====

        """#
        return (compilation, rendered, name, Data(proof.utf8))
    }
}
