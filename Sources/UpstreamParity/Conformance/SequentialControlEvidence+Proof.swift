import SwiftTLA

extension SequentialControlEvidence {
    static func successfulEntryTypes(in layout: CompiledLayout) -> [String]? {
        var types: [String] = []
        for field in layout.variables where field.declaration.origin == .source {
            let domain: String
            switch (field.resolvedValueType, field.generatedSwiftType) {
            case (.int?, _), (nil, "Int"?), (nil, "Swift.Int"?):
                domain = "AuthoredSequentialMachineInts"
            case (.bool?, _), (nil, "Bool"?), (nil, "Swift.Bool"?):
                domain = "BOOLEAN"
            default: return nil
            }
            types.append("\(field.formalName) \\in \(domain)")
        }
        return types
    }

    /// The exporter receives the already retained backend inputs, including action metadata used by the real renderer.
    func proofSource(for rendered: RenderedSpecification, layout: CompiledLayout,
                             physicalAuthored: Machine, proofModule: String = "SwiftTLASequentialControlProof",
                             includeNative: Bool = true, declared: DeclaredSyntax? = nil,
                             entryTypes: [String]? = nil) throws -> String? {
        let proveSuccessfulRoutes = entryTypes != nil
        let module = rendered.tlaBundle.root.name
        let actions = rendered.actions
        let counters = layout.variables.filter { $0.declaration.origin == .programCounter }
        guard isTLADeclarationName(module), isTLADeclarationName(proofModule), module != proofModule,
              counters.count == 1, let counter = counters.first?.formalName,
              layout.variables.allSatisfy({ $0.declaration.origin == .source || $0.declaration.origin == .programCounter }),
              isTLADeclarationName(counter), !actions.isEmpty,
              actions.allSatisfy({ $0.arguments.isEmpty && isTLADeclarationName($0.renderedName) }),
              let physicalTrace = physicalAuthored.canonicalTraces(sourceWrites: true),
              let compilerTrace = authored.canonicalTraces(sourceWrites: true),
              let scheduledTrace = scheduled.canonicalTraces(sourceWrites: false),
              let loweredTrace = lowered.canonicalTraces(sourceWrites: false) else { return nil }

        func location(_ value: ControlLocationReference) -> TLAValue {
            .tuple([.string(value.declarationIdentity.owner?.canonicalEncoding ?? ""), .string(value.declarationIdentity.sourceName)])
        }
        func control(_ value: Control) -> TLAValue {
            switch value {
            case .transfer(let destination): .tuple([.string("transfer"), location(destination)])
            case .unchanged: .tuple([.string("unchanged")])
            case .disabled: .tuple([.string("disabled")])
            }
        }
        func table(_ machine: Machine, includeWrites: Bool) -> TLAValue? {
            var actions: [TLAValue] = []
            for action in machine.actions {
                var branches: [TLAValue] = []
                for branch in action.branches {
                    var trace: [TLAValue] = []
                    for observation in branch.observations {
                        let prefix: [TLAValue]
                        let expression: StateExpr
                        switch observation {
                        case .guardValue(let guardExpression):
                            prefix = [.string("guard")]
                            expression = guardExpression
                        case .capture(let name, let read):
                            prefix = [.string("capture"), .string(name)]
                            expression = read
                        case .write(let name, let value) where includeWrites:
                            prefix = [.string("write"), .string(name)]
                            expression = value
                        case .write, .endCapture:
                            continue
                        }
                        guard let term = expression.scalarEvidenceTerm else { return nil }
                        trace.append(.tuple(prefix + [term]))
                    }
                    branches.append(.tuple([.tuple(trace), control(branch.control)]))
                }
                actions.append(.tuple([.string(action.label), .tuple(branches)]))
            }
            return .tuple([location(machine.initial), .tuple(actions)])
        }
        guard let physicalTerms = table(physicalTrace, includeWrites: true),
              let compilerTerms = table(compilerTrace, includeWrites: true),
              let scheduledTerms = table(scheduledTrace, includeWrites: true),
              let loweredTerms = table(loweredTrace, includeWrites: true),
              let scheduledRoutes = table(scheduled, includeWrites: false),
              let loweredRoutes = table(lowered, includeWrites: false) else { return nil }

        func formal(_ reference: ControlLocationReference) throws -> String? {
            let identity = reference.declarationIdentity
            let matches = layout.controlLocations.filter {
                $0.owner == identity.owner && $0.sourceName.utf8.elementsEqual(identity.sourceName.utf8)
            }
            guard matches.count == 1, let match = matches.first else { return nil }
            return try CompiledValue.controlLocation(match.id).rendered(using: layout).description
        }

        func sourceField(named name: String) -> String? {
            let matches = layout.variables.filter {
                $0.declaration.origin == .source && $0.declaration.name.utf8.elementsEqual(name.utf8)
            }
            guard matches.count == 1 else { return nil }
            return matches.first?.formalName
        }

        func scalarTerm(_ expression: StateExpr) throws -> String? {
            func binary(_ left: StateExpr, _ op: String, _ right: StateExpr) throws -> String? {
                guard let lhs = try scalarTerm(left), let rhs = try scalarTerm(right) else { return nil }
                return "(\(lhs) \(op) \(rhs))"
            }
            func shortCircuit(_ left: StateExpr, _ right: StateExpr, whenTrue: Bool) throws -> String? {
                guard let lhs = try scalarTerm(left), let rhs = try scalarTerm(right) else { return nil }
                return whenTrue ? "(IF \(lhs) THEN \(rhs) ELSE FALSE)" : "(IF \(lhs) THEN TRUE ELSE \(rhs))"
            }

            switch expression {
            case .variable(let name): return sourceField(named: name)
            case .value(.int(let value)): return TLAValue.int(value).description
            case .value(.bool(let value)): return TLAValue.bool(value).description
            case .programCounter: return counter
            case .controlLocation(let reference): return try formal(reference)
            case .equal(let left, let right): return try binary(left, "=", right)
            case .notEqual(let left, let right): return try binary(left, "#", right)
            case .lessThan(let left, let right): return try binary(left, "<", right)
            case .lessOrEqual(let left, let right): return try binary(left, "<=", right)
            case .greaterThan(let left, let right): return try binary(left, ">", right)
            case .greaterOrEqual(let left, let right): return try binary(left, ">=", right)
            case .add(let left, let right): return try binary(left, "+", right)
            case .subtract(let left, let right): return try binary(left, "-", right)
            case .and(let left, let right): return try shortCircuit(left, right, whenTrue: true)
            case .or(let left, let right): return try shortCircuit(left, right, whenTrue: false)
            case .not(let operand):
                guard let test = try scalarTerm(operand) else { return nil }
                return "(~\(test))"
            default: return nil
            }
        }

        func whenDefined(_ checks: [String], then value: String) -> String {
            checks.reversed().reduce(value) { "(IF \($1) THEN \($0) ELSE FALSE)" }
        }
        typealias EvaluationCheck = (test: String, payload: String)
        func defined(_ expression: StateExpr) throws -> [EvaluationCheck] {
            switch expression {
            case .add(let left, let right), .subtract(let left, let right):
                guard let value = try scalarTerm(expression),
                      let lhs = try scalarTerm(left), let rhs = try scalarTerm(right) else {
                    throw CompiledValueType.diagnostic("sequentialControl", "expected a scalar arithmetic term")
                }
                let operation: String
                if case .add = expression { operation = "addition" } else { operation = "subtraction" }
                let payload = "<<\"integerOverflow\", \"\(operation)\", <<\(lhs), \(rhs)>>>>"
                return try defined(left) + defined(right) + [(value + " \\in AuthoredSequentialMachineInts", payload)]
            case .and(let left, let right), .or(let left, let right):
                let lhs = try defined(left)
                let rhs = try defined(right)
                guard !rhs.isEmpty else { return lhs }
                guard let condition = try scalarTerm(left) else {
                    throw CompiledValueType.diagnostic("sequentialControl", "expected a scalar Boolean term")
                }
                let test: String
                if case .and = expression { test = condition } else { test = "(~\(condition))" }
                return lhs + rhs.map { ("(IF \(test) THEN \($0.test) ELSE TRUE)", $0.payload) }
            case .equal(let left, let right), .notEqual(let left, let right),
                 .lessThan(let left, let right), .lessOrEqual(let left, let right),
                 .greaterThan(let left, let right), .greaterOrEqual(let left, let right):
                return try defined(left) + defined(right)
            case .not(let operand): return try defined(operand)
            default: return []
            }
        }

        let sourceFields = layout.variables.filter { $0.declaration.origin == .source }
        guard let sourceEntry = try formal(physicalTrace.initial),
              actions.count == physicalTrace.actions.count,
              zip(actions, physicalTrace.actions).allSatisfy({
                  $0.0.sourceName.utf8.elementsEqual($0.1.label.utf8)
              }) else { return nil }

        let unchangedState = sourceFields.map(\.formalName)
        var routeStatements: [String] = []
        var successfulSteps: [String] = []
        var failureSteps: [String] = []
        var failureNames: [String] = []
        var hasFallibleGuards = false
        var successfulRouteStatements: [String] = []
        var successProofSteps: [String] = []
        var successProofFacts: [String] = []
        var writeFreeStatements: [String] = []
        var writeFreeGuards: [String] = []
        var writeFreeSteps: [String] = []
        var allowedGuards: [String] = []
        var allowedSteps: [String] = []
        var nativeEntries: [String] = []
        var nativeWrites: [String] = []
        for (action, declared) in zip(actions, physicalTrace.actions) {
            var routes: [String] = []
            var successfulRoutes: [String] = []
            var failureRoutes: [String] = []
            var writeFreeRoutes: [String] = []
            var entries: Set<String> = []
            var writes: Set<String> = []
            for branch in declared.branches {
                guard case .guardValue(.equal(.programCounter, .controlLocation(let entry)))? = branch.observations.first,
                      let initial = try formal(entry) else { return nil }
                entries.insert(initial)
                var conditions = ["\(counter) = \(initial)"]
                for observation in branch.observations.dropFirst() {
                    guard case .guardValue(let expression) = observation else { continue }
                    guard let predicate = try scalarTerm(expression) else { return nil }
                    conditions.append(predicate)
                }
                let reached = conditions.joined(separator: " /\\ ")
                allowedGuards.append("(\(reached))")
                let transfer: String
                switch branch.control {
                case .transfer(let location):
                    guard let end = try formal(location) else { return nil }
                    transfer = "\(counter)' = \(end)"
                    writes.insert("<<\"control\", \(end)>>")
                case .unchanged:
                    transfer = "UNCHANGED \(counter)"
                    writes.insert("<<\"state\", \(TLAValue.string(counter))>>")
                case .disabled:
                    transfer = "FALSE"
                }
                var frame = [reached, transfer]
                var written: Set<String> = []
                for observation in branch.observations {
                    guard case .write(let name, let expression) = observation else { continue }
                    guard let field = sourceField(named: name), written.insert(field).inserted,
                          let value = try scalarTerm(expression) else { return nil }
                    frame.append("\(field)' = \(value)")
                }
                let unchanged = unchangedState.filter { !written.contains($0) }
                if !unchanged.isEmpty {
                    frame.append("UNCHANGED <<\(unchanged.joined(separator: ", "))>>")
                }
                let completeRoute = "(\(frame.joined(separator: " /\\ ")))"
                routes.append(completeRoute)
                if proveSuccessfulRoutes {
                    var checks = [(test: "\(counter) = \(initial)", onFailure: "<<>>")]
                    var completed: [String] = []
                    let label = TLAValue.string(action.sourceName)
                    for observation in branch.observations.dropFirst() {
                        let expression: StateExpr
                        let isCapture: Bool
                        switch observation {
                        case .guardValue(let guardValue):
                            expression = guardValue
                            isCapture = false
                        case .capture(_, let capture):
                            expression = capture
                            isCapture = true
                        case .write, .endCapture:
                            continue
                        }
                        guard let value = try scalarTerm(expression) else { return nil }
                        let evaluation = try defined(expression)
                        if isCapture {
                            let site = completed.count + 1
                            let prior = "<<\(completed.joined(separator: ", "))>>"
                            checks += evaluation.map { check in
                                (check.test, "<<[label |-> \(label), pc |-> \(counter), site |-> \(site), payload |-> \(check.payload), completed |-> \(prior)]>>")
                            }
                            completed.append(value)
                        } else {
                            hasFallibleGuards = hasFallibleGuards || !evaluation.isEmpty
                            checks += evaluation.map { ($0.test, "<<>>") }
                            checks.append((value, "<<>>"))
                        }
                    }
                    let updates = frame.dropFirst().joined(separator: " /\\ ")
                    successfulRoutes.append("(\(whenDefined(checks.map(\.test), then: updates)))")
                    let first = checks.reversed().reduce("<<>>") { rest, check in
                        "(IF \(check.test) THEN \(rest) ELSE \(check.onFailure))"
                    }
                    failureRoutes.append(first)
                }
                if branch.observations.allSatisfy({
                    guard case .guardValue = $0 else { return false }
                    return true
                }) {
                    writeFreeGuards.append("(\(reached))")
                    writeFreeRoutes.append(completeRoute)
                }
            }
            let effect = routes.isEmpty ? "FALSE" : routes.joined(separator: " \\/ ")
            routeStatements.append("/\\ (\(action.renderedName) => (\(effect)))")
            allowedSteps.append("(\(effect))")
            if proveSuccessfulRoutes {
                let success = successfulRoutes.isEmpty ? "FALSE" : successfulRoutes.joined(separator: " \\/ ")
                let slot = successfulSteps.count + 1
                let step = "AuthoredSequentialSuccessfulAction\(slot)"
                successfulSteps.append("LOCAL \(step) == \(success)")
                let failure = "AuthoredSequentialActionFailure\(slot)"
                let branches = failureRoutes.enumerated().map { index, branch in
                    let name = "\(failure)Branch\(index + 1)"
                    failureSteps.append("\(name) == \(branch)")
                    return name
                }
                let first = branches.reversed().reduce("<<>>") { rest, branch in
                    "(IF \(branch) # <<>> THEN \(branch) ELSE \(rest))"
                }
                failureSteps.append("\(failure) == \(first)")
                failureNames.append(failure)
                successfulRouteStatements.append("/\\ (\(action.renderedName) <=> \(step))")
                successProofSteps.append(#"""
                <1>complete\#(slot). \#(step) => \#(action.renderedName)
                    BY ONLY AuthoredSequentialTypedEntry, SMT DEF AuthoredSequentialTypedEntry, AuthoredSequentialMachineInts, \#(step), \#(action.renderedName)
                <1>sound\#(slot). \#(action.renderedName) => \#(step)
                    BY ONLY AuthoredSequentialTypedEntry, SMT DEF AuthoredSequentialTypedEntry, AuthoredSequentialMachineInts, \#(step), \#(action.renderedName)
                """#)
                successProofFacts += ["<1>complete\(slot)", "<1>sound\(slot)"]
            }
            if !writeFreeRoutes.isEmpty {
                let writeFree = writeFreeRoutes.joined(separator: " \\/ ")
                writeFreeSteps.append("(\(writeFree))")
                writeFreeStatements.append("/\\ ((\(writeFree)) => \(action.renderedName))")
            }
            nativeEntries.append("{\(entries.sorted().joined(separator: ", "))}")
            nativeWrites.append("{\(writes.sorted().joined(separator: ", "))}")
        }
        let writeFreeGuard = writeFreeGuards.isEmpty ? "FALSE" : writeFreeGuards.joined(separator: " \\/ ")
        let writeFreeStep = writeFreeSteps.isEmpty ? "FALSE" : writeFreeSteps.joined(separator: " \\/ ")
        let writeFreeTheorem = writeFreeStatements.isEmpty ? "/\\ TRUE" : writeFreeStatements.joined(separator: "\n    ")
        let authoredGuard = allowedGuards.isEmpty ? "FALSE" : allowedGuards.joined(separator: " \\/ ")
        let labels = TLAValue.tuple(actions.map { .string($0.sourceName) })
        let declarations = actions.map(\.renderedName).joined(separator: ", ")
        let next = actions.map(\.renderedName).joined(separator: " \\/ ")
        let native = includeNative ? #"""
        SequentialControlEntries == <<\#(nativeEntries.joined(separator: ", "))>>
        SequentialControlWrites == <<\#(nativeWrites.joined(separator: ", "))>>

        NativeControlUsesAuthoredRoutes ==
            \A index \in DOMAIN NativeActionRows :
                LET plan == NativeActionRows[index][2] IN
                /\ plan.guards[1] \in SequentialControlEntries[index]
                /\ \E write \in DOMAIN plan.writes : plan.writes[write][1] = \#(TLAValue.string(counter))
                /\ \A write \in DOMAIN plan.writes :
                       plan.writes[write][1] = \#(TLAValue.string(counter)) =>
                           plan.writes[write][2] \in SequentialControlWrites[index]

        THEOREM ActualNativeControlTransfersUseSelectedTargets ==
            NativeControlUsesAuthoredRoutes
            BY ONLY IsaM("simp") DEF NativeControlUsesAuthoredRoutes, NativeActionRows, SequentialControlEntries, SequentialControlWrites

        THEOREM ActualNativeSequentialInventoryUsesAuthoredLabels ==
            /\ DOMAIN NativeActionRows = DOMAIN AuthoredSequentialLabels
            /\ \A index \in DOMAIN NativeActionRows : NativeActionRows[index][1] = AuthoredSequentialLabels[index]
        PROOF
        <1>authored. AuthoredSequentialLabels = SequentialLabelProjection(LoweredSequentialSemantics[2])
            BY ONLY ActualLoweredControlPreservesAuthoredRouteShape, SMT DEF AuthoredSequentialLabels
        <1>lowered. SequentialLabelProjection(LoweredSequentialSemantics[2]) = SequentialActionLabels
            BY ONLY SMT DEF SequentialLabelProjection, LoweredSequentialSemantics, SequentialActionLabels
        <1>native. SequentialActionLabels = SequentialLabelProjection(NativeActionRows)
            BY ONLY SMT DEF SequentialLabelProjection, SequentialActionLabels, NativeActionRows
        <1>. QED BY ONLY <1>authored, <1>lowered, <1>native, SMT DEF SequentialLabelProjection
        """# : ""
        let nativeImport = includeNative ? ", SwiftTLANativeActions" : ""
        let declaredProof: String
        if let declared {
            guard let proof = declared.proof(loweredTrace: loweredTrace, compilerAuthoredSteps: compilerAuthoredSteps)
            else { return nil }
            declaredProof = proof
        } else {
            declaredProof = ""
        }
        let declaredImport = declared == nil ? "" : ", Naturals, Sequences"
        let successImport = proveSuccessfulRoutes ? ", Integers" : ""
        let failuresBySlot = failureNames.enumerated().map { "slot = \($0.offset + 1) -> \($0.element)" }
        let failuresByLabel = zip(actions, failureNames).map { action, failure in
            "label = \(TLAValue.string(action.sourceName)) -> \(failure)"
        }
        let noReachedFailure = failureNames.map { "\($0) = <<>>" }.joined(separator: " /\\ ")
        let failureProof = !hasFallibleGuards && proveSuccessfulRoutes ? #"""
        \#(failureSteps.joined(separator: "\n"))
        AuthoredSequentialVisitorFailure(slot) == CASE \#(failuresBySlot.joined(separator: " [] ")) [] OTHER -> <<>>
        AuthoredSequentialFirstFailure(label) == CASE \#(failuresByLabel.joined(separator: " [] ")) [] OTHER -> <<>>
        AuthoredSequentialNoReachedFailure == \#(noReachedFailure)
        """# : ""
        let successProof = proveSuccessfulRoutes ? #"""

        AuthoredSequentialMachineInts == \#(TLAValue.int(Int.min))..\#(TLAValue.int(Int.max))
        AuthoredSequentialTypedEntry == \#(entryTypes.flatMap { $0.isEmpty ? nil : $0.joined(separator: " /\\ ") } ?? "TRUE")
        \#(successfulSteps.joined(separator: "\n"))
        AuthoredSequentialSuccessfulStep == \#(successfulSteps.indices.map { "AuthoredSequentialSuccessfulAction\($0 + 1)" }.joined(separator: " \\/ "))

        THEOREM ActualTLAUsesTheDefinedAuthoredRoutes ==
            ASSUME AuthoredSequentialTypedEntry
            PROVE
                \#(successfulRouteStatements.joined(separator: "\n        "))
        PROOF
        \#(successProofSteps.joined(separator: "\n"))
        <1>. QED BY ONLY \#(successProofFacts.joined(separator: ", ")), PTL

        THEOREM AuthoredSequentialSuccessIsExactlyTheEmittedStep ==
            AuthoredSequentialTypedEntry => (Next <=> AuthoredSequentialSuccessfulStep)
        PROOF
        <1>. SUFFICES ASSUME AuthoredSequentialTypedEntry
                      PROVE Next <=> AuthoredSequentialSuccessfulStep BY PTL
        <1>. QED BY ONLY AuthoredSequentialTypedEntry, ActualTLAUsesTheDefinedAuthoredRoutes,
            ActualRenderedSequentialActionInventory, PTL DEF AuthoredSequentialSuccessfulStep

        \#(failureProof)

        THEOREM AuthoredSequentialSuccessPreservesTypedEntry ==
            AuthoredSequentialTypedEntry /\ AuthoredSequentialSuccessfulStep => AuthoredSequentialTypedEntry'
            BY ONLY SMT DEF AuthoredSequentialTypedEntry, AuthoredSequentialMachineInts,
                AuthoredSequentialSuccessfulStep, \#(successfulSteps.indices.map { "AuthoredSequentialSuccessfulAction\($0 + 1)" }.joined(separator: ", "))
        """# : ""
        return #"""
        ---- MODULE \#(proofModule) ----
        EXTENDS \#(module), TLAPS\#(nativeImport)\#(declaredImport)\#(successImport)

        PhysicalAuthoredSequentialTrace == \#(physicalTerms)
        CompilerAuthoredSequentialTrace == \#(compilerTerms)
        ScheduledSequentialSemantics == \#(scheduledTerms)
        LoweredSequentialSemantics == \#(loweredTerms)
        ScheduledSequentialTrace == \#(scheduledRoutes)
        LoweredSequentialTrace == \#(loweredRoutes)
        SequentialActionLabels == \#(labels)
        LOCAL SequentialLabelProjection(rows) == [index \in DOMAIN rows |-> rows[index][1]]
        AuthoredSequentialLabels == SequentialLabelProjection(PhysicalAuthoredSequentialTrace[2])
        AuthoredSequentialInitialControl == \#(counter) = \#(sourceEntry)
        AuthoredSequentialGuard == \#(authoredGuard)
        AuthoredSequentialStep == \#(allowedSteps.joined(separator: " \\/ "))
        AuthoredSequentialWriteFreeGuard == \#(writeFreeGuard)
        AuthoredSequentialWriteFreeStep == \#(writeFreeStep)

        THEOREM ActualLoweredControlPreservesAuthoredRouteShape ==
            /\ PhysicalAuthoredSequentialTrace = CompilerAuthoredSequentialTrace
            /\ PhysicalAuthoredSequentialTrace = ScheduledSequentialSemantics
            /\ ScheduledSequentialSemantics = LoweredSequentialSemantics
            /\ ScheduledSequentialTrace = LoweredSequentialTrace
        PROOF
        <1>source. PhysicalAuthoredSequentialTrace = CompilerAuthoredSequentialTrace
            BY ONLY SMT DEF PhysicalAuthoredSequentialTrace, CompilerAuthoredSequentialTrace
        <1>scheduled. PhysicalAuthoredSequentialTrace = ScheduledSequentialSemantics
            BY ONLY SMT DEF PhysicalAuthoredSequentialTrace, ScheduledSequentialSemantics
        <1>lowered. ScheduledSequentialSemantics = LoweredSequentialSemantics
            BY ONLY SMT DEF ScheduledSequentialSemantics, LoweredSequentialSemantics
        <1>scope. ScheduledSequentialTrace = LoweredSequentialTrace
            BY ONLY SMT DEF ScheduledSequentialTrace, LoweredSequentialTrace
        <1>. QED BY ONLY <1>source, <1>scheduled, <1>lowered, <1>scope

        THEOREM ActualRenderedSequentialActionInventory ==
            /\ DOMAIN SequentialActionLabels = DOMAIN LoweredSequentialTrace[2]
            /\ \A index \in DOMAIN SequentialActionLabels :
                   SequentialActionLabels[index] = LoweredSequentialTrace[2][index][1]
            /\ (Next <=> (\#(next)))
        PROOF
        <1>lowered. SequentialActionLabels = SequentialLabelProjection(LoweredSequentialTrace[2])
            BY ONLY SMT DEF SequentialLabelProjection, SequentialActionLabels, LoweredSequentialTrace
        <1>next. Next <=> (\#(next))
            BY ONLY DEF Next
        <1>. QED BY ONLY <1>lowered, <1>next, SMT DEF SequentialLabelProjection

        THEOREM ActualTLAControlTransfersFollowSelectedRoutes ==
            \#(routeStatements.joined(separator: "\n    "))
            BY ONLY SMT DEF \#(declarations)

        THEOREM ActualTLAAdmitsWriteFreeAuthoredRoutes ==
            \#(writeFreeTheorem)
            BY ONLY SMT DEF \#(declarations)

        THEOREM ActualSequentialStepUsesAuthoredRoutes ==
            /\ (Next => AuthoredSequentialStep)
            /\ (~AuthoredSequentialGuard => ~ENABLED Next)
            /\ (AuthoredSequentialWriteFreeGuard => ENABLED Next)
        PROOF
        <1>routes. Next => AuthoredSequentialStep
            BY ONLY ActualRenderedSequentialActionInventory, ActualTLAControlTransfersFollowSelectedRoutes, SMT
                DEF AuthoredSequentialStep
        <1>guard. Next => AuthoredSequentialGuard
            BY ONLY <1>routes, SMT DEF AuthoredSequentialStep, AuthoredSequentialGuard
        <1>nextBoolean. Next \in BOOLEAN
            BY ONLY SMT DEF Next, \#(declarations)
        <1>guardBoolean. AuthoredSequentialGuard \in BOOLEAN
            BY ONLY SMT DEF AuthoredSequentialGuard
        <1>enabled. (ENABLED Next) => ENABLED AuthoredSequentialGuard
            BY ONLY <1>guard, <1>nextBoolean, <1>guardBoolean, ENABLEDaxioms
        <1>state. (ENABLED AuthoredSequentialGuard) <=> AuthoredSequentialGuard
            BY ONLY ExpandENABLED, SMT DEF AuthoredSequentialGuard
        <1>disabled. ~AuthoredSequentialGuard => ~ENABLED Next
            BY ONLY <1>enabled, <1>state, PTL
        <1>emits. AuthoredSequentialWriteFreeStep => Next
            BY ONLY ActualTLAAdmitsWriteFreeAuthoredRoutes, ActualRenderedSequentialActionInventory, SMT
                DEF AuthoredSequentialWriteFreeStep
        <1>writeFreeBoolean. AuthoredSequentialWriteFreeStep \in BOOLEAN
            BY ONLY SMT DEF AuthoredSequentialWriteFreeStep
        <1>mapped. (ENABLED AuthoredSequentialWriteFreeStep) => ENABLED Next
            BY ONLY <1>emits, <1>writeFreeBoolean, <1>nextBoolean, ENABLEDaxioms
        <1>witness. AuthoredSequentialWriteFreeGuard => ENABLED AuthoredSequentialWriteFreeStep
            BY ONLY ExpandENABLED, SMT DEF AuthoredSequentialWriteFreeGuard, AuthoredSequentialWriteFreeStep
        <1>available. AuthoredSequentialWriteFreeGuard => ENABLED Next
            BY ONLY <1>witness, <1>mapped, PTL
        <1>. QED BY ONLY <1>routes, <1>disabled, <1>available

        THEOREM ActualSpecUsesOnlyAuthoredSequentialControl ==
            /\ (Spec => AuthoredSequentialInitialControl)
            /\ (Spec => [][AuthoredSequentialStep]_vars)
            /\ (~AuthoredSequentialGuard => ~ENABLED Next)
            /\ (AuthoredSequentialWriteFreeGuard => ENABLED Next)
            /\ PhysicalAuthoredSequentialTrace = LoweredSequentialSemantics
        PROOF
        <1>entry. Init => AuthoredSequentialInitialControl
            BY ONLY SMT DEF Init, AuthoredSequentialInitialControl
        <1>initial. Spec => AuthoredSequentialInitialControl
            BY ONLY <1>entry, PTL DEF Spec
        <1>step. Next => AuthoredSequentialStep
            BY ONLY ActualSequentialStepUsesAuthoredRoutes
        <1>stuttering. [Next]_vars => [AuthoredSequentialStep]_vars
            BY ONLY <1>step, PTL
        <1>always. ([][Next]_vars) => ([][AuthoredSequentialStep]_vars)
            BY ONLY <1>stuttering, PTL
        <1>binding. PhysicalAuthoredSequentialTrace = LoweredSequentialSemantics
            BY ONLY ActualLoweredControlPreservesAuthoredRouteShape, SMT
        <1>. QED BY ONLY <1>initial, <1>always, <1>binding,
            ActualSequentialStepUsesAuthoredRoutes, PTL DEF Spec, vars

        \#(native)\#(declaredProof)\#(successProof)

        ====

        """#
    }
}

extension StateExpr {
    // Read and literal tags agree with CopyReferenceValue in OrderedScalarCopyRule.tla.
    var scalarEvidenceTerm: TLAValue? {
        func binary(_ operation: String, _ lhs: StateExpr, _ rhs: StateExpr) -> TLAValue? {
            guard let left = lhs.scalarEvidenceTerm, let right = rhs.scalarEvidenceTerm else { return nil }
            return .tuple([.string(operation), left, right])
        }

        switch self {
        case .variable(let name): return .tuple([.string("state"), .string(name)])
        case .value(.int(let value)): return .tuple([.string("literal"), .int(value)])
        case .value(.bool(let value)): return .tuple([.string("literal"), .bool(value)])
        case .programCounter: return .tuple([.string("programCounter")])
        case .controlLocation(let location):
            return .tuple([.string("controlLocation"), .string(location.declarationIdentity.owner?.canonicalEncoding ?? ""),
                           .string(location.declarationIdentity.sourceName)])
        case .equal(let lhs, let rhs): return binary("equal", lhs, rhs)
        case .notEqual(let lhs, let rhs): return binary("notEqual", lhs, rhs)
        case .lessThan(let lhs, let rhs): return binary("lessThan", lhs, rhs)
        case .lessOrEqual(let lhs, let rhs): return binary("lessOrEqual", lhs, rhs)
        case .greaterThan(let lhs, let rhs): return binary("greaterThan", lhs, rhs)
        case .greaterOrEqual(let lhs, let rhs): return binary("greaterOrEqual", lhs, rhs)
        case .and(let lhs, let rhs): return binary("and", lhs, rhs)
        case .or(let lhs, let rhs): return binary("or", lhs, rhs)
        case .add(let lhs, let rhs): return binary("add", lhs, rhs)
        case .subtract(let lhs, let rhs): return binary("subtract", lhs, rhs)
        case .not(let operand):
            guard let term = operand.scalarEvidenceTerm else { return nil }
            return .tuple([.string("not"), term])
        default: return nil
        }
    }
}

extension SequentialControlEvidence {
    struct DeclaredSyntax {
        let algorithm: String
        let steps: [AlgorithmStepModel]

        init(algorithm: String, steps: [AlgorithmStepModel]) {
            self.algorithm = algorithm
            self.steps = steps
        }

        fileprivate func proof(loweredTrace: Machine, compilerAuthoredSteps: [AlgorithmStepModel]) -> String? {
            func writeSites(_ statements: [AlgorithmStatementModel]) -> [TLAValue] {
                statements.flatMap { statement -> [TLAValue] in
                    func arms(_ first: [AlgorithmStatementModel], _ second: [AlgorithmStatementModel]) -> [TLAValue] {
                        [.tuple([.tuple(writeSites(first)), .tuple(writeSites(second))])]
                    }
                    switch statement {
                    case .set(let target, _): return [.string(target.root)]
                    case .parallel(let assignments): return assignments.map { .string($0.target.root) }
                    case .ifElse(_, let yes, let no), .either(let yes, let no): return arms(yes, no)
                    case .letBinding(_, _, let body), .with(_, _, let body), .choose(_, _, let body):
                        return writeSites(body)
                    default: return []
                    }
                }
            }
            func orderedWriteSites(_ steps: [AlgorithmStepModel]) -> TLAValue {
                .tuple(steps.map { .tuple([.string($0.label.name), .tuple(writeSites($0.statements))]) })
            }

            func statementKinds(_ statements: [AlgorithmStatementModel]) -> [TLAValue] {
                statements.flatMap { statement -> [TLAValue] in
                    return switch statement {
                    case .goto: [.string("goto")]
                    case .stop: [.string("stop")]
                    case .call: [.string("call")]
                    case .return: [.string("return")]
                    case .letBinding(_, _, let body), .with(_, _, let body), .choose(_, _, let body):
                        statementKinds(body)
                    case .ifElse(_, let yes, let no), .either(let yes, let no):
                        statementKinds(yes) + statementKinds(no)
                    default:
                        [.string("statement")]
                    }
                }
            }

            let physicalWriteSites = orderedWriteSites(steps)
            let compilerWriteSites = orderedWriteSites(compilerAuthoredSteps)
            guard physicalWriteSites == compilerWriteSites else { return nil }

            var rows: [TLAValue] = []
            for step in steps {
                let loop: TLAValue
                if let condition = step.loopCondition {
                    guard let term = condition.scalarEvidenceTerm else { return nil }
                    loop = term
                } else {
                    loop = .tuple([])
                }
                rows.append(.record(TLARecord([
                    .init("label", .string(step.label.name)),
                    .init("loop", loop),
                    .init("bodyKinds", .tuple(statementKinds(step.statements))),
                ])))
            }
            guard !rows.isEmpty else { return nil }

            let owner = ControlOwner.sequential(algorithm: algorithm).canonicalEncoding
            let doneLabel = CompilerControlSymbol.done.rawValue
            let done = TLAValue.tuple([
                .string(ControlOwner.generated(algorithm: algorithm, purpose: doneLabel).canonicalEncoding),
                .string(doneLabel),
            ])
            let terminating = TLAValue.string(CompilerControlSymbol.terminatingAction.rawValue)
            let rowPositions = rows.indices.map { String($0 + 1) }.joined(separator: ", ")
            let rowFacts = rows.indices.map { "<2>row\($0 + 1)" }.joined(separator: ", ")
            let rowProofs = rows.indices.map { index in
                let slot = index + 1
                let count = loweredTrace.actions.indices.contains(index) ? loweredTrace.actions[index].branches.count : 0
                // Branch expansion visits the outer While's false arm after the body.
                let positions = (0..<count).map { String($0 + 1) }.joined(separator: ", ")
                let branchFacts = (0..<count).map { ", <4>branch\($0 + 1)" }.joined()
                let branchProofs = (0..<count).map { offset in
                    let branch = offset + 1
                    return #"""
                    <4>branch\#(branch). DeclaredBranchMatches(constructor, entry, following, exit, branches[\#(branch)])
                        <5>guards.
                            /\ branches[\#(branch)][1][1] = DeclaredEntryGuard(entry)
                            /\ (DeclaredDynamicWhile(constructor) /\ branches[\#(branch)] # exit =>
                                    branches[\#(branch)][1][2] = <<"guard", constructor.loop>>)
                            BY ONLY IsaM("simp")
                                DEF branches, action, constructor, entry, exit, DeclaredDynamicWhile, DeclaredWhileExit,
                                    DeclaredEntryGuard, DeclaredFollowing, DeclaredEntry, DeclaredOwner, DeclaredDone,
                                    DeclaredCount, DeclaredSequentialConstructors, LoweredSequentialSemantics
                        <5>disabled. (branches[\#(branch)][2] = <<"disabled">>) <=>
                                    (branches[\#(branch)][1][Len(branches[\#(branch)][1])] = DeclaredFalseGuard)
                            BY ONLY IsaM("simp")
                                DEF branches, action, DeclaredFalseGuard, LoweredSequentialSemantics
                        <5>control. ~DeclaredBodyTransfers(constructor) /\ branches[\#(branch)] # exit /\
                                    branches[\#(branch)][2] # <<"disabled">> /\
                                    (constructor.loop = <<>> \/ DeclaredDynamicWhile(constructor)) =>
                                branches[\#(branch)][2] = <<"transfer", IF constructor.loop = <<>> THEN following ELSE entry>>
                            BY ONLY IsaM("simp")
                                DEF branches, action, constructor, entry, following, exit, DeclaredDynamicWhile, DeclaredBodyTransfers,
                                    DeclaredWhileExit, DeclaredEntryGuard, DeclaredFollowing, DeclaredEntry, DeclaredOwner,
                                    DeclaredDone, DeclaredCount, DeclaredSequentialConstructors, LoweredSequentialSemantics
                        <5>. QED BY ONLY <5>guards, <5>disabled, <5>control DEF DeclaredBranchMatches
                    """#
                }.joined(separator: "\n        ")
                return #"""
                <2>row\#(slot). DeclaredRowMatches(\#(slot), LoweredSequentialSemantics[2][\#(slot)])
                    <3>. DEFINE action == LoweredSequentialSemantics[2][\#(slot)]
                                constructor == DeclaredSequentialConstructors[\#(slot)]
                                branches == action[2]
                                entry == DeclaredEntry(DeclaredSequentialConstructors, \#(slot))
                                following == DeclaredFollowing(DeclaredSequentialConstructors, DeclaredCount, \#(slot))
                                exit == DeclaredWhileExit(DeclaredSequentialConstructors, DeclaredCount, \#(slot))
                    <3>name. action[1] = constructor.label
                        BY ONLY IsaM("simp") DEF action, constructor, LoweredSequentialSemantics, DeclaredSequentialConstructors
                    <3>branchInterval. 1..\#(count) = {\#(positions)}
                        BY ONLY SMT
                    <3>branchDomain. DOMAIN branches = {\#(positions)}
                        BY ONLY <3>branchInterval, IsaM("simp") DEF branches, action, LoweredSequentialSemantics
                    <3>exit. DeclaredDynamicWhile(constructor) =>
                            \E branch \in DOMAIN branches : branches[branch] = exit
                        <4>candidate. DeclaredDynamicWhile(constructor) =>
                                /\ \#(count) \in DOMAIN branches
                                /\ branches[\#(count)] = exit
                            BY ONLY <3>branchDomain, IsaM("simp")
                                DEF branches, action, constructor, exit, DeclaredDynamicWhile, DeclaredWhileExit, DeclaredCount,
                                    DeclaredEntryGuard, DeclaredFollowing, DeclaredEntry, DeclaredOwner, DeclaredDone,
                                    DeclaredSequentialConstructors, LoweredSequentialSemantics
                        <4>. QED BY ONLY <4>candidate, SMT
                    <3>branches. \A branch \in DOMAIN branches :
                            DeclaredBranchMatches(constructor, entry, following, exit, branches[branch])
                        \#(branchProofs)
                        <4>. QED BY ONLY <3>branchDomain\#(branchFacts), SMT
                    <3>. QED BY ONLY <3>name, <3>exit, <3>branches
                        DEF DeclaredRowMatches, action, constructor, branches, entry, following, exit
                """#
            }.joined(separator: "\n    ")
            return #"""


        PhysicalAuthoredSequentialWriteSites == \#(physicalWriteSites)
        CompilerAuthoredSequentialWriteSites == \#(compilerWriteSites)
        DeclaredSequentialConstructors == \#(TLAValue.tuple(rows))
        LOCAL DeclaredCount == \#(rows.count)
        LOCAL DeclaredOwner == \#(TLAValue.string(owner))
        LOCAL DeclaredDone == \#(done)
        LOCAL DeclaredTerminalLabel == \#(terminating)
        LOCAL DeclaredEntry(rows, slot) == <<DeclaredOwner, rows[slot].label>>
        LOCAL DeclaredFollowing(rows, count, slot) ==
            IF slot < count THEN DeclaredEntry(rows, slot + 1) ELSE DeclaredDone
        LOCAL DeclaredEntryGuard(location) ==
            <<"guard", <<"equal", <<"programCounter">>, <<"controlLocation", location[1], location[2]>>>>>>
        LOCAL DeclaredDynamicWhile(row) ==
            row.loop \notin {<<>>, <<"literal", TRUE>>, <<"literal", FALSE>>}
        LOCAL DeclaredBodyTransfers(row) ==
            \E index \in DOMAIN row.bodyKinds : row.bodyKinds[index] \in {"goto", "stop", "call", "return"}
        LOCAL DeclaredWhileExit(rows, count, slot) ==
            << <<DeclaredEntryGuard(DeclaredEntry(rows, slot)), <<"guard", <<"not", rows[slot].loop>>>> >>,
                <<"transfer", DeclaredFollowing(rows, count, slot)>> >>
        LOCAL DeclaredTerminalRow ==
            <<DeclaredTerminalLabel, <<<< <<DeclaredEntryGuard(DeclaredDone)>>, <<"unchanged">> >>>> >>

        LOCAL DeclaredFalseGuard == <<"guard", <<"literal", FALSE>>>>

        LOCAL DeclaredBranchMatches(constructor, entry, following, exit, observed) ==
            /\ observed[1][1] = DeclaredEntryGuard(entry)
            /\ ((observed[2] = <<"disabled">>) <=> (observed[1][Len(observed[1])] = DeclaredFalseGuard))
            /\ (DeclaredDynamicWhile(constructor) /\ observed # exit =>
                    observed[1][2] = <<"guard", constructor.loop>>)
            /\ (~DeclaredBodyTransfers(constructor) /\ observed # exit /\ observed[2] # <<"disabled">> /\
                    (constructor.loop = <<>> \/ DeclaredDynamicWhile(constructor)) =>
                    observed[2] = <<"transfer", IF constructor.loop = <<>> THEN following ELSE entry>>)

        LOCAL DeclaredRowMatches(slot, action) ==
            LET rows == DeclaredSequentialConstructors
                branches == action[2]
                constructor == rows[slot]
                entry == DeclaredEntry(rows, slot)
                following == DeclaredFollowing(rows, DeclaredCount, slot)
                exit == DeclaredWhileExit(rows, DeclaredCount, slot)
            IN /\ action[1] = constructor.label
               /\ (DeclaredDynamicWhile(constructor) =>
                    \E branch \in DOMAIN branches : branches[branch] = exit)
               /\ \A branch \in DOMAIN branches :
                    DeclaredBranchMatches(constructor, entry, following, exit, branches[branch])

        LOCAL DeclaredRowsMatch(trace) ==
            \A slot \in 1..DeclaredCount : DeclaredRowMatches(slot, trace[2][slot])

        DeclaredSequentialConstructorsMatch(trace) ==
            /\ DeclaredCount \in Nat \ {0}
            /\ DOMAIN DeclaredSequentialConstructors = 1..DeclaredCount
            /\ trace[1] = DeclaredEntry(DeclaredSequentialConstructors, 1)
            /\ DOMAIN trace[2] = 1..(DeclaredCount + 1)
            /\ trace[2][DeclaredCount + 1] = DeclaredTerminalRow
            /\ DeclaredRowsMatch(trace)
            /\ PhysicalAuthoredSequentialWriteSites = CompilerAuthoredSequentialWriteSites

        THEOREM ActualLoweredRoutesUseTheDeclaredSequentialConstructors ==
            DeclaredSequentialConstructorsMatch(LoweredSequentialSemantics)
        PROOF
        <1>layout.
            /\ DeclaredCount \in Nat \ {0}
            /\ DOMAIN DeclaredSequentialConstructors = 1..DeclaredCount
            /\ LoweredSequentialSemantics[1] = DeclaredEntry(DeclaredSequentialConstructors, 1)
            /\ DOMAIN LoweredSequentialSemantics[2] = 1..(DeclaredCount + 1)
            /\ LoweredSequentialSemantics[2][DeclaredCount + 1] = DeclaredTerminalRow
            BY ONLY SMT DEF DeclaredCount, DeclaredSequentialConstructors, DeclaredEntry, DeclaredOwner,
                DeclaredTerminalRow, DeclaredTerminalLabel, DeclaredEntryGuard, DeclaredDone, LoweredSequentialSemantics
        <1>branches. DeclaredRowsMatch(LoweredSequentialSemantics)
            <2>slots. 1..DeclaredCount = {\#(rowPositions)}
                BY ONLY SMT DEF DeclaredCount
            \#(rowProofs)
            <2>. QED BY ONLY <2>slots, \#(rowFacts), SMT DEF DeclaredRowsMatch
        <1>writeSites. PhysicalAuthoredSequentialWriteSites = CompilerAuthoredSequentialWriteSites
            BY ONLY IsaM("simp") DEF PhysicalAuthoredSequentialWriteSites, CompilerAuthoredSequentialWriteSites
        <1>. QED BY ONLY <1>layout, <1>branches, <1>writeSites DEF DeclaredSequentialConstructorsMatch
        """#
        }
    }
}
