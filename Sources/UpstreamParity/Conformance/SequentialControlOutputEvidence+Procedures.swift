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
        guard let selection = try procedureNext(rendered, layout: program.layout, actions: program.behavior.actions,
                                                source: source.algorithm, selected: [source.action])
        else { return nil }
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
            /\ ProcedureNextUsesTheRegisteredRoutes
            /\ ProcedureNextUsesTheCheckedBodies
            /\ ProcedureRequiredBodySlots \subseteq ProcedureCheckedBodySlots
            /\ (\A worker : AuthoredProcedureLoopInput(worker) => AuthoredProcedureLoopControl(worker))
        \#(bodyResult)
        \#(assertionResult)
            BY ONLY ActualProcedureLoopConfigurationIsSelected, ActualNextPartitionsAllRegisteredProcedureRoutes,
                ActualRegisteredProcedureBodiesMatchTheCheckedRows, ActualRegisteredProcedureBodyCoverage,
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

    // Interpret the authored control transfer and its successful state updates.
    // Unsupported statement shapes keep their emitted contribution to Next.
    private struct ProcedureBody {
        let inputs: [String]
        let predicate: String
    }

    private static func authoredProcedureBody(
        _ route: SequentialControlEvidence.ProcedureActionDomain,
        in algorithm: AlgorithmModel, layout: CompiledLayout
    ) -> ProcedureBody? {
        let processes = algorithm.components.compactMap { component -> AlgorithmProcessModel? in
            guard case .process(let process) = component else { return nil }
            return process
        }
        let procedures = algorithm.components.compactMap { component -> AlgorithmProcedureModel? in
            guard case .procedure(let procedure) = component else { return nil }
            return procedure
        }
        guard let pc = layout.variables.first(where: { $0.declaration.origin == .programCounter })?.formalName,
              let stack = layout.variables.first(where: { $0.declaration.origin == .procedureStack })?.formalName
        else { return nil }
        func location(_ owner: ControlOwner, _ label: String) -> String? {
            let matches = layout.controlLocations.filter {
                $0.owner == owner && $0.sourceName.utf8.elementsEqual(label.utf8)
            }
            return matches.count == 1 ? matches.first.map { TLAValue.string($0.formalName).description } : nil
        }
        let doneLabel = CompilerControlSymbol.done.rawValue
        guard let done = location(.generated(algorithm: algorithm.name, purpose: doneLabel), doneLabel) else { return nil }
        let allFields = layout.variables.map(\.formalName)
        func frame(_ changed: Set<String>) -> String {
            let fields = allFields.filter { !changed.contains($0) }
            return fields.isEmpty ? "TRUE" : "UNCHANGED <<\(fields.joined(separator: ", "))>>"
        }
        func conjunction(_ clauses: [String]) -> String {
            clauses.isEmpty ? "TRUE" : clauses.joined(separator: #" /\ "#)
        }
        guard let step = route.step else {
            let guards = processes.compactMap { process -> String? in
                guard let members = process.domain.literalSetMembers else { return nil }
                return #"(\A worker \in \#(TLAValue.set(Set(members))) : \#(pc)[worker] = \#(done))"#
            }
            guard guards.count == processes.count else { return nil }
            let atDone = processes.isEmpty ? ["\(pc) = \(done)"] : guards
            return .init(inputs: [], predicate: conjunction(atDone + [frame([])]))
        }
        let scoped = route.workers != nil
        var indexed = scoped ? Set([pc]) : []
        var domains: [String] = []
        func atWorker(_ field: String) -> String {
            guard scoped else { return field }
            indexed.insert(field)
            return "\(field)[worker]"
        }
        func workerUpdate(_ field: String, to value: String) -> String {
            guard scoped else { return "\(field)' = \(value)" }
            indexed.insert(field)
            return "\(field)' = [\(field) EXCEPT ![worker] = \(value)]"
        }
        func rootName(_ root: String, origin: VariableOrigin) -> String? {
            let matches = layout.variables.filter {
                $0.declaration.origin == origin && $0.declaration.name.utf8.elementsEqual(root.utf8)
            }
            return matches.count == 1 ? matches.first?.formalName : nil
        }
        let allocated = procedures.flatMap { $0.parameters.map(\.root) + $0.locals.map(\.root) }
        guard Set(allocated).count == allocated.count else { return nil }

        let shared = Set(algorithm.components.compactMap { component -> String? in
            guard case .shared(let state) = component else { return nil }
            return state.root
        })
        var localOrigins: [String: VariableOrigin] = [:]
        switch route.owner {
        case .process(_, let index, _):
            guard processes.indices.contains(index) else { return nil }
            for component in processes[index].components {
                if case .local(let local) = component {
                    localOrigins[local.root] = local.exposed ? .source : .compiler
                }
            }
        case .procedure(_, let name):
            guard let owner = procedures.first(where: { $0.name == name }) else { return nil }
            for local in owner.parameters.map(\.root) + owner.locals.map(\.root) { localOrigins[local] = .compiler }
        default: break
        }
        func term(_ expression: StateExpr) -> String? {
            procedureTerm(expression, variable: { root in
                if let origin = localOrigins[root], let field = rootName(root, origin: origin) {
                    return atWorker(field)
                }
                guard shared.contains(root) else { return nil }
                return rootName(root, origin: .source)
            }, workerLookup: scoped ? { root in
                guard localOrigins[root] == nil, shared.contains(root),
                      let field = rootName(root, origin: .source) else { return nil }
                return atWorker(field)
            } : nil)
        }

        guard let entry = location(route.owner, step.label.name) else { return nil }
        let following: String
        if let label = route.following {
            guard let next = location(route.owner, label) else { return nil }
            following = next
        } else {
            following = done
        }
        let statements = step.statements.filter { $0 != .skip }
        let continuation = step.loopCondition == nil ? following : entry
        var updates: [String] = []
        var changed: Set<String> = [pc]
        switch statements.last {
        case .none:
            updates = [workerUpdate(pc, to: continuation)]
        case .some(.stop) where statements.count == 1:
            updates = [workerUpdate(pc, to: done)]
        case .some(.goto(let label)) where statements.count == 1:
            guard let destination = location(route.owner, label.name) else { return nil }
            updates = [workerUpdate(pc, to: destination)]
        case .some(.call(let name, let arguments)) where statements.count == 1:
            guard let callee = procedures.first(where: { $0.name == name }), let first = callee.steps.first,
                  let destination = location(.procedure(algorithm: algorithm.name, name: name), first.label.name),
                  arguments.count == callee.parameters.count,
                  let slots = procedureFrameFields(allocated, resolving: { rootName($0, origin: .compiler) })
            else { return nil }
            for (parameter, argument) in zip(callee.parameters, arguments) {
                guard let field = rootName(parameter.root, origin: .compiler),
                      let value = term(argument) else { return nil }
                changed.insert(field)
                updates.append(workerUpdate(field, to: value))
            }
            for local in callee.locals {
                guard case .value(let value) = local.initialization,
                      let field = rootName(local.root, origin: .compiler),
                      let initial = term(.value(value)) else { return nil }
                changed.insert(field)
                updates.append(workerUpdate(field, to: initial))
            }
            let saved = [
                "\(CompilerControlSymbol.procedure.rawValue) |-> \(TLAValue.string(name))",
                "\(CompilerControlSymbol.programCounter.rawValue) |-> \(continuation)"
            ] + slots.map { "\($0.0) |-> \(atWorker($0.1))" }
            let beforeStack = atWorker(stack)
            updates += [workerUpdate(pc, to: destination),
                        workerUpdate(stack, to: #"<<[\#(saved.joined(separator: ", "))]>> \o \#(beforeStack)"#)]
            changed.insert(stack)
        case .some(.return):
            guard case .procedure = route.owner,
                  let slots = procedureFrameFields(allocated, resolving: { rootName($0, origin: .compiler) })
            else { return nil }
            let beforeStack = atWorker(stack)
            updates = ["Len(\(beforeStack)) > 0",
                       workerUpdate(pc, to: "(Head(\(beforeStack))).pc"),
                       workerUpdate(stack, to: "Tail(\(beforeStack))")]
            for (key, field) in slots { updates.append(workerUpdate(field, to: "(Head(\(beforeStack))).\(key)")) }
            changed.formUnion([stack] + slots.map { $0.1 })
            let preceding = statements.dropLast()
            if !preceding.isEmpty {
                guard preceding.count == 1, case .some(.set(let target, let expression)) = preceding.first,
                      shared.contains(target.root), localOrigins[target.root] == nil,
                      let field = rootName(target.root, origin: .source)
                else { return nil }
                let value: String
                if case .add(let left, let right) = expression {
                    guard let lhs = term(left), let rhs = term(right) else { return nil }
                    let integers = "\(TLAValue.int(.min))..\(TLAValue.int(.max))"
                    domains += [#"\#(lhs) \in \#(integers)"#, #"\#(rhs) \in \#(integers)"#]
                    value = "(\(lhs) + \(rhs))"
                    updates.insert(#"\#(value) \in \#(integers)"#, at: 0)
                } else {
                    guard let leaf = term(expression) else { return nil }
                    value = leaf
                }
                switch target {
                case .root:
                    updates.append("\(field)' = \(value)")
                case .function(.root(_), let key):
                    guard let index = term(key) else { return nil }
                    domains.append(#"\#(index) \in DOMAIN \#(field)"#)
                    updates.append("\(field)' = [\(field) EXCEPT ![\(index)] = \(value)]")
                default: return nil
                }
                changed.insert(field)
            }
        default: return nil
        }
        let success = conjunction(updates + [frame(changed)])
        let atEntry = "\(atWorker(pc)) = \(entry)"
        var active = [atEntry]
        let effect: String
        if let guardExpression = step.loopCondition {
            guard let condition = term(guardExpression) else { return nil }
            active.append(condition)
            let exit = conjunction([workerUpdate(pc, to: following), frame([pc])])
            effect = "(IF \(condition) THEN (\(success)) ELSE (\(exit)))"
        } else {
            effect = success
        }
        let predicate = conjunction([atEntry, effect])
        let indexedInputs = indexed.sorted().map { #"worker \in DOMAIN \#($0)"# }
        let inputs = indexedInputs + domains.map { "((\(conjunction(active))) => \($0))" }
        return .init(inputs: inputs, predicate: predicate)
    }

    private static func procedureFrameFields(
        _ roots: [String], resolving name: (String) -> String?
    ) -> [(String, String)]? {
        let fields = roots.compactMap { root in name(root).map { (root, $0) } }
        guard fields.count == roots.count,
              !roots.contains(CompilerControlSymbol.programCounter.rawValue),
              !roots.contains(CompilerControlSymbol.procedure.rawValue),
              roots.allSatisfy({ $0.range(of: #"^[A-Za-z][A-Za-z0-9_]*$"#, options: .regularExpression) != nil })
        else { return nil }
        return fields
    }

    private static func authoredProcedureCatalog(
        _ rows: [(RenderedAction, SequentialControlEvidence.ProcedureActionDomain)],
        source: AlgorithmModel, layout: CompiledLayout
    ) -> (proof: String, unchecked: Set<Int>) {
        var unchecked: Set<Int> = []
        var inputs: [String] = []
        var values: [String] = []
        var declarations: [String] = []
        var proofs: [String] = []
        var equality: [String] = []
        var interpreted: [String: Int] = [:]
        for (index, pair) in rows.enumerated() {
            let (action, route) = pair
            let slot = index + 1
            let observed = "ProcedureRegisteredAction\(slot)"
            let basis = interpreted[action.emittedBaseName] ?? slot
            let input = "ProcedureBodyInput\(basis)"
            let predicate = "ProcedureAuthoredBody\(basis)"
            let scoped = !action.arguments.isEmpty
            let arguments = scoped ? "(\(observed).arguments[1])" : ""
            if basis == slot {
                guard let body = authoredProcedureBody(route, in: source, layout: layout) else {
                    unchecked.insert(slot)
                    values.append(action.renderedName)
                    continue
                }
                interpreted[action.emittedBaseName] = slot
                let parameters = scoped ? "(worker)" : ""
                let clauses = body.inputs.isEmpty ? "TRUE" : body.inputs.joined(separator: #" /\ "#)
                declarations.append(#"""
                LOCAL \#(input)\#(parameters) == \#(clauses)
                LOCAL \#(predicate)\#(parameters) == \#(body.predicate)
                """#)
                let quantified = scoped ? #"\A worker : "# : ""
                proofs.append(#"""
                    <2>meaning\#(basis). \#(quantified)\#(input)\#(parameters) =>
                        (\#(action.emittedBaseName)\#(parameters) = \#(predicate)\#(parameters))
                        BY ONLY SMT DEF \#(input), \#(predicate), \#(action.emittedBaseName)
                """#)
            }
            inputs.append(input + arguments)
            values.append(predicate + arguments)
            let expansion = scoped ? ", \(action.renderedName), \(observed)" : ""
            proofs.append(#"""
                <2>row\#(slot). \#(action.renderedName) = \#(predicate)\#(arguments)
                    BY ONLY <2>inputs, <2>meaning\#(basis), SMT DEF ProcedureAuthoredInput\#(expansion)
            """#)
            equality.append("<2>row\(slot)")
        }
        let domain = TLAValue.set(Set(unchecked.map(TLAValue.int)))
        let allInputs = inputs.isEmpty ? "TRUE" : inputs.joined(separator: #" /\ "#)
        let bodyFacts = (equality + [#"IsaM("simp")"#]).joined(separator: ", ")
        let proof = #"""
        \#(declarations.joined(separator: "\n"))
        ProcedureUncheckedBodySlots == \#(domain)
        ProcedureCheckedBodySlots == DOMAIN ProcedureRegisteredActions \ ProcedureUncheckedBodySlots
        ProcedureAuthoredInput == \#(allInputs)
        ProcedureBodyValues == <<\#(values.joined(separator: ", "))>>
        LOCAL ProcedureBodyCatalogLabeled(observed) ==
            ProcedureCatalogDispatch!CatalogLabeledBranches(ProcedureBodyValues, ProcedureRegisteredActions, observed)
        ProcedureCheckedBodyStep(observed) ==
            \E slot \in ProcedureCheckedBodySlots :
                ProcedureRegisteredActions[slot] = observed /\ ProcedureBodyValues[slot]
        ProcedureEmittedOnlyStep(observed) ==
            \E slot \in DOMAIN ProcedureRegisteredActions \cap ProcedureUncheckedBodySlots :
                ProcedureRegisteredActions[slot] = observed /\ ProcedureCatalogActualActionValues[slot]
        ProcedureComposedStep(observed) ==
            ProcedureCheckedBodyStep(observed) \/ ProcedureEmittedOnlyStep(observed)

        ProcedureNextUsesTheCheckedBodies ==
            ProcedureAuthoredInput =>
                /\ (\A observed : ProcedureRegisteredLabeled(observed) <=> ProcedureComposedStep(observed))
                /\ (Next <=> (\E observed : ProcedureComposedStep(observed)))
                /\ ([Next]_vars <=> ((\E observed : ProcedureComposedStep(observed))
                                    \/ ProcedureCatalogActualFrameAfter = ProcedureCatalogActualFrameBefore))

        THEOREM ActualRegisteredProcedureBodiesMatchTheCheckedRows ==
            ProcedureNextUsesTheCheckedBodies
        PROOF
        <1>compose. ASSUME ProcedureAuthoredInput
            PROVE /\ (\A observed : ProcedureRegisteredLabeled(observed) <=> ProcedureComposedStep(observed))
                  /\ (Next <=> (\E observed : ProcedureComposedStep(observed)))
                  /\ ([Next]_vars <=> ((\E observed : ProcedureComposedStep(observed))
                                      \/ ProcedureCatalogActualFrameAfter = ProcedureCatalogActualFrameBefore))
            <2>inputs. ProcedureAuthoredInput BY ONLY ProcedureAuthoredInput
        \#(proofs.joined(separator: "\n"))
            <2>bodies. ProcedureCatalogActualActionValues = ProcedureBodyValues
                BY ONLY \#(bodyFacts) DEF ProcedureCatalogActualActionValues, ProcedureBodyValues
            <2>width. DOMAIN ProcedureBodyValues = DOMAIN ProcedureRegisteredActions
                BY ONLY IsaM("simp") DEF ProcedureBodyValues, ProcedureRegisteredActions
            <2>split. \A observed : ProcedureBodyCatalogLabeled(observed) <=> ProcedureComposedStep(observed)
                BY ONLY <2>bodies, SMT DEF ProcedureBodyCatalogLabeled, ProcedureComposedStep,
                    ProcedureCheckedBodyStep, ProcedureEmittedOnlyStep, ProcedureCheckedBodySlots,
                    ProcedureCatalogDispatch!CatalogLabeledBranches
            <2>labels. \A observed : ProcedureRegisteredLabeled(observed) <=> ProcedureComposedStep(observed)
                BY ONLY <2>bodies, <2>split, SMT DEF ProcedureRegisteredLabeled, ProcedureBodyCatalogLabeled
            <2>catalog. (\E ProcedureCatalogIndex \in DOMAIN ProcedureCatalogActualActionValues : ProcedureCatalogActualActionValues[ProcedureCatalogIndex])
                          <=> (\E observed : ProcedureBodyCatalogLabeled(observed))
                BY ONLY <2>bodies, <2>width, ProcedureCatalogDispatch!CatalogLabeledBranchesComposeTheFiniteUnion, SMT
                    DEF ProcedureBodyCatalogLabeled
            <2>union. (\E ProcedureCatalogIndex \in DOMAIN ProcedureCatalogActualActionValues : ProcedureCatalogActualActionValues[ProcedureCatalogIndex])
                       <=> (\E observed : ProcedureComposedStep(observed))
                BY ONLY <2>catalog, <2>split, SMT
            <2>actual.
                /\ (Next <=> (\E ProcedureCatalogIndex \in DOMAIN ProcedureCatalogActualActionValues : ProcedureCatalogActualActionValues[ProcedureCatalogIndex]))
                /\ ([Next]_vars <=> ((\E ProcedureCatalogIndex \in DOMAIN ProcedureCatalogActualActionValues : ProcedureCatalogActualActionValues[ProcedureCatalogIndex])
                                    \/ ProcedureCatalogActualFrameAfter = ProcedureCatalogActualFrameBefore))
                BY ONLY ProcedureCatalogActualNextUsesTheCompleteLabeledActionCatalog, PTL
            <2>. QED BY ONLY <2>labels, <2>union, <2>actual, PTL
        <1>. QED BY ONLY <1>compose DEF ProcedureNextUsesTheCheckedBodies
        """#
        return (proof, unchecked)
    }

    private static func procedureNext(
        _ rendered: RenderedSpecification, layout: CompiledLayout, actions: [CompiledAction],
        source: AlgorithmModel, selected: Set<String>, completeBodies: Bool = false
    ) throws -> String? {
        let tla = rendered.tlaBundle.root.tla
        guard !tla.contains("ProcedureCatalog"), !tla.contains("ProcedureRegisteredInvocations"),
              !tla.contains("ProcedureRegisteredAction"), !tla.contains("ProcedureRegisteredLabeled"),
              !tla.contains("ProcedureSelected"), !tla.contains("ProcedureRemainingStep"),
              !tla.contains("ProcedureNextUsesThe"), !tla.contains("ProcedureAuthored"),
              !tla.contains("ProcedureBody"), !tla.contains("ProcedureUncheckedBodySlots"),
              !tla.contains("ProcedureCheckedBody"), !tla.contains("ProcedureRequiredBodySlots"),
              !tla.contains("ProcedureEmittedOnlyStep"),
              !tla.contains("ProcedureComposedStep"),
              !tla.contains("ActualRegisteredProcedureBodies"), !tla.contains("ActualRegisteredProcedureBodyCoverage")
        else { return nil }
        let declarations = layout.actions.filter { !$0.declaration.name.isEmpty }
        guard let registered = SequentialControlEvidence.procedureActionDomains(in: source),
              declarations.count == registered.count, declarations.last?.isTermination == true,
              !selected.isEmpty, selected.isSubset(of: Set(registered.map(\.label))) else { return nil }
        var rows: [(RenderedAction, SequentialControlEvidence.ProcedureActionDomain)] = []
        for (declaration, source) in zip(declarations, registered) {
            guard declaration.declaration.name.utf8.elementsEqual(source.label.utf8),
                  actions.indices.contains(declaration.id.ordinal) else { return nil }
            let action = actions[declaration.id.ordinal]
            guard action.id == declaration.id else { return nil }
            let formal = declaration.renderedName
            if let workers = source.workers {
                guard action.bindings.count == 1, let members = action.bindings.first?.literalMembers else { return nil }
                let values = try members.map { try $0.rendered(using: layout) }
                let authored = values.compactMap { value in
                    workers.firstIndex(of: value).map { workers[$0] }
                }
                guard values.count == workers.count, Set(authored) == workers else { return nil }
                rows += authored.enumerated().map { index, worker in
                    (.init(sourceName: source.label, emittedBaseName: formal, arguments: [worker],
                           renderedName: "\(formal)__\(index)"), source)
                }
            } else {
                guard action.bindings.isEmpty else { return nil }
                rows.append((.init(sourceName: source.label, emittedBaseName: formal, arguments: [], renderedName: formal), source))
            }
        }
        let expected = rows.map { $0.0 }
        guard let catalog = StraightLineRenderedActionCheck.finiteActionCatalog(
            in: rendered, frameFields: layout.variables.map(\.formalName), matching: expected)
        else { return nil }
        let physical = catalog.proofSource(prefix: "ProcedureCatalog")
        let authoredBodies = authoredProcedureCatalog(rows, source: source, layout: layout)
        let required = Set(rows.enumerated().compactMap { index, row -> Int? in
            guard let step = row.1.step else { return index + 1 }
            return step.loopCondition == nil && step.statements.filter { $0 != .skip } == [.stop]
                ? index + 1 : nil
        })
        guard required.isDisjoint(with: authoredBodies.unchecked),
              !completeBodies || authoredBodies.unchecked.isEmpty else { return nil }
        let coverage = completeBodies
            ? #"""
              THEOREM ActualRegisteredProcedureBodyCoverage ==
                  ProcedureUncheckedBodySlots = {}
                  BY ONLY DEF ProcedureUncheckedBodySlots
              """#
            : #"""
              ProcedureRequiredBodySlots == \#(TLAValue.set(Set(required.map(TLAValue.int))))
              THEOREM ActualRegisteredProcedureBodyCoverage ==
                  ProcedureRequiredBodySlots \subseteq ProcedureCheckedBodySlots
                  BY ONLY IsaM("simp") DEF ProcedureRequiredBodySlots, ProcedureCheckedBodySlots,
                      ProcedureUncheckedBodySlots, ProcedureRegisteredActions
              """#
        let selectedLabels = TLAValue.set(Set(selected.map(TLAValue.string)))
        let observations = expected.indices.map { "ProcedureRegisteredAction\($0 + 1)" }
        let records = zip(observations, expected).map { name, row in
            let observed = TLAValue.record(TLARecord([
                .init("label", .string(row.sourceName)), .init("arguments", .tuple(row.arguments))
            ]))
            return "LOCAL \(name) == \(observed)"
        }.joined(separator: "\n")
        let invocations = zip(observations, expected).map { name, row in
            row.arguments.isEmpty ? row.emittedBaseName : "\(row.emittedBaseName)(\(name).arguments[1])"
        }.joined(separator: ", ")
        let aliases = expected.filter { !$0.arguments.isEmpty }.map(\.renderedName)
        let expansion = (["ProcedureCatalogActualActionValues", "ProcedureRegisteredInvocations"] + aliases + observations)
            .joined(separator: ", ")
        return #"""
        \#(physical.dispatch)
        \#(physical.body)

        ProcedureSelectedLabels == \#(selectedLabels)
        \#(records)
        ProcedureRegisteredActions == <<\#(observations.joined(separator: ", "))>>
        ProcedureRegisteredInvocations == <<\#(invocations)>>
        LOCAL ProcedureRegisteredLabeled(observed) ==
            ProcedureCatalogDispatch!CatalogLabeledBranches(
                ProcedureCatalogActualActionValues, ProcedureRegisteredActions, observed)
        ProcedureSelectedStep(observed) ==
            observed.label \in ProcedureSelectedLabels /\ ProcedureRegisteredLabeled(observed)
        ProcedureRemainingStep(observed) ==
            observed.label \notin ProcedureSelectedLabels /\ ProcedureRegisteredLabeled(observed)
        ProcedureNextUsesTheRegisteredRoutes ==
            /\ ProcedureCatalogActualActionValues = ProcedureRegisteredInvocations
            /\ (Next <=> (\E observed : ProcedureSelectedStep(observed) \/ ProcedureRemainingStep(observed)))
            /\ (\A observed : ~(ProcedureSelectedStep(observed) /\ ProcedureRemainingStep(observed)))
            /\ ([Next]_vars <=> ((\E observed : ProcedureSelectedStep(observed) \/ ProcedureRemainingStep(observed))
                                \/ ProcedureCatalogActualFrameAfter = ProcedureCatalogActualFrameBefore))

        THEOREM ActualNextPartitionsAllRegisteredProcedureRoutes ==
            ProcedureNextUsesTheRegisteredRoutes
        PROOF
        <1>bindings. ProcedureCatalogActualActionValues = ProcedureRegisteredInvocations
            BY ONLY IsaM("simp") DEF \#(expansion)
        <1>dimensions. DOMAIN ProcedureRegisteredInvocations = DOMAIN ProcedureRegisteredActions
            BY ONLY IsaM("simp") DEF ProcedureRegisteredInvocations, ProcedureRegisteredActions
        <1>inventory.
            /\ (Next <=> (\E ProcedureCatalogIndex \in DOMAIN ProcedureCatalogActualActionValues : ProcedureCatalogActualActionValues[ProcedureCatalogIndex]))
            /\ ([Next]_vars <=> ((\E ProcedureCatalogIndex \in DOMAIN ProcedureCatalogActualActionValues : ProcedureCatalogActualActionValues[ProcedureCatalogIndex])
                                \/ ProcedureCatalogActualFrameAfter = ProcedureCatalogActualFrameBefore))
            BY ONLY ProcedureCatalogActualNextUsesTheCompleteLabeledActionCatalog, PTL
        <1>union. (\E ProcedureCatalogIndex \in DOMAIN ProcedureCatalogActualActionValues : ProcedureCatalogActualActionValues[ProcedureCatalogIndex])
                   <=> (\E observed : ProcedureRegisteredLabeled(observed))
            BY ONLY <1>bindings, <1>dimensions, ProcedureCatalogDispatch!CatalogLabeledBranchesComposeTheFiniteUnion, SMT
                DEF ProcedureRegisteredLabeled
        <1>split.
            /\ ((\E observed : ProcedureRegisteredLabeled(observed))
                <=> (\E observed : ProcedureSelectedStep(observed) \/ ProcedureRemainingStep(observed)))
            /\ (\A observed : ~(ProcedureSelectedStep(observed) /\ ProcedureRemainingStep(observed)))
            BY ONLY SMT DEF ProcedureSelectedStep, ProcedureRemainingStep
        <1>. QED BY ONLY <1>bindings, <1>inventory, <1>union, <1>split, PTL
            DEF ProcedureNextUsesTheRegisteredRoutes

        \#(authoredBodies.proof)

        \#(coverage)
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
        let counterField = CompilerControlSymbol.programCounter.rawValue
        let procedureField = CompilerControlSymbol.procedure.rawValue
        guard Set(frameKeys).count == frameKeys.count,
              let saved = procedureFrameFields(frameKeys, resolving: slotName) else { return nil }
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
        guard let selection = try procedureNext(rendered, layout: layout, actions: compilation.semantics.behavior.actions,
                                                source: source, selected: [steps[index].label.name, returnRows[0].sourceName],
                                                completeBodies: true)
        else { return nil }
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
            /\ ProcedureNextUsesTheRegisteredRoutes
            /\ ProcedureNextUsesTheCheckedBodies
            /\ ProcedureUncheckedBodySlots = {}
            /\ AuthoredCallWhileSavesContinuation
            /\ AuthoredCallWhileAdvancesOnFalse
            /\ AuthoredCallWhileRestoresContinuation
            BY ONLY ActualCallWhileConfigurationIsSelected, ActualNextPartitionsAllRegisteredProcedureRoutes,
                ActualRegisteredProcedureBodiesMatchTheCheckedRows, ActualRegisteredProcedureBodyCoverage,
                ActualCallWhileSavesTheAuthoredContinuation, ActualFalseCallWhileTakesTheAuthoredNextLabel,
                ActualCallWhileReturnRestoresTheSavedContinuation, PTL

        ====

        """#
        return (compilation, rendered, name, Data(proof.utf8))
    }
}
