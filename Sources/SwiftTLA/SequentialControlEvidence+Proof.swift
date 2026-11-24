extension SequentialControlEvidence {
    /// The exporter receives the already retained backend inputs, including action metadata used by the real renderer.
    package func proofSource(for rendered: RenderedSpecification, layout: CompiledLayout,
                             physicalAuthored: Machine, proofModule: String = "SwiftTLASequentialControlProof",
                             includeNative: Bool = true, declared: DeclaredSyntax? = nil) throws -> String? {
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
            .tuple([.string(value.owner?.canonicalEncoding ?? ""), .string(value.sourceName)])
        }
        func control(_ value: Control) -> TLAValue {
            switch value {
            case .transfer(let destination): .tuple([.string("transfer"), location(destination)])
            case .unchanged: .tuple([.string("unchanged")])
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
            let matches = layout.controlLocations.filter {
                $0.owner == reference.owner && $0.sourceName.utf8.elementsEqual(reference.sourceName.utf8)
            }
            guard matches.count == 1, let match = matches.first else { return nil }
            return try CompiledValue.controlLocation(match.id).rendered(using: layout).description
        }

        func guardTerm(_ expression: StateExpr) throws -> String? {
            func binary(_ left: StateExpr, _ op: String, _ right: StateExpr) throws -> String? {
                guard let lhs = try guardTerm(left), let rhs = try guardTerm(right) else { return nil }
                return "(\(lhs) \(op) \(rhs))"
            }
            func shortCircuit(_ left: StateExpr, _ right: StateExpr, whenTrue: Bool) throws -> String? {
                guard let lhs = try guardTerm(left), let rhs = try guardTerm(right) else { return nil }
                return whenTrue ? "(IF \(lhs) THEN \(rhs) ELSE FALSE)" : "(IF \(lhs) THEN TRUE ELSE \(rhs))"
            }

            switch expression {
            case .variable(let name):
                let matches = layout.variables.filter {
                    $0.declaration.origin == .source && $0.declaration.name.utf8.elementsEqual(name.utf8)
                }
                guard matches.count == 1 else { return nil }
                return matches.first?.formalName
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
                guard let test = try guardTerm(operand) else { return nil }
                return "(~\(test))"
            default: return nil
            }
        }

        guard let sourceEntry = try formal(physicalTrace.initial),
              actions.count == physicalTrace.actions.count,
              zip(actions, physicalTrace.actions).allSatisfy({
                  $0.0.sourceName.utf8.elementsEqual($0.1.label.utf8)
              }) else { return nil }

        let unchangedState = layout.variables.filter { $0.declaration.origin == .source }.map(\.formalName)
        let frame = unchangedState.isEmpty ? "" : " /\\ UNCHANGED <<\(unchangedState.joined(separator: ", "))>>"
        var routeStatements: [String] = []
        var writeFreeStatements: [String] = []
        var writeFreeGuards: [String] = []
        var writeFreeSteps: [String] = []
        var allowedGuards: [String] = []
        var allowedSteps: [String] = []
        var nativeEntries: [String] = []
        var nativeWrites: [String] = []
        for (action, declared) in zip(actions, physicalTrace.actions) {
            var routes: [String] = []
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
                    guard let predicate = try guardTerm(expression) else { return nil }
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
                }
                routes.append("(\(reached) /\\ \(transfer))")
                if branch.observations.allSatisfy({
                    guard case .guardValue = $0 else { return false }
                    return true
                }) {
                    writeFreeGuards.append("(\(reached))")
                    writeFreeRoutes.append("(\(reached) /\\ \(transfer)\(frame))")
                }
            }
            let effect = routes.isEmpty ? "FALSE" : routes.joined(separator: " \\/ ")
            routeStatements.append("/\\ (\(action.renderedName) => (\(effect)))")
            allowedSteps.append("(\(effect))")
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
            guard let proof = declared.proof(loweredTrace: loweredTrace) else { return nil }
            declaredProof = proof
        } else {
            declaredProof = ""
        }
        let declaredImport = declared == nil ? "" : ", Naturals"
        return #"""
        ---- MODULE \#(proofModule) ----
        EXTENDS \#(module), TLAPS\#(nativeImport)\#(declaredImport)

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

        \#(native)\#(declaredProof)

        ====

        """#
    }
}

extension StateExpr {
    // Read and literal tags agree with CopyReferenceValue in OrderedScalarCopyRule.tla.
    package var scalarEvidenceTerm: TLAValue? {
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
            return .tuple([.string("controlLocation"), .string(location.owner?.canonicalEncoding ?? ""),
                           .string(location.sourceName)])
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
    package struct DeclaredSyntax {
        package let algorithm: String
        package let steps: [AlgorithmStepModel]

        package init(algorithm: String, steps: [AlgorithmStepModel]) {
            self.algorithm = algorithm
            self.steps = steps
        }

        fileprivate func proof(loweredTrace: Machine) -> String? {
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
                        <5>control. ~DeclaredBodyTransfers(constructor) /\ branches[\#(branch)] # exit /\
                                    (constructor.loop = <<>> \/ DeclaredDynamicWhile(constructor)) =>
                                branches[\#(branch)][2] = <<"transfer", IF constructor.loop = <<>> THEN following ELSE entry>>
                            BY ONLY IsaM("simp")
                                DEF branches, action, constructor, entry, following, exit, DeclaredDynamicWhile, DeclaredBodyTransfers,
                                    DeclaredWhileExit, DeclaredEntryGuard, DeclaredFollowing, DeclaredEntry, DeclaredOwner,
                                    DeclaredDone, DeclaredCount, DeclaredSequentialConstructors, LoweredSequentialSemantics
                        <5>. QED BY ONLY <5>guards, <5>control DEF DeclaredBranchMatches
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

        LOCAL DeclaredBranchMatches(constructor, entry, following, exit, observed) ==
            /\ observed[1][1] = DeclaredEntryGuard(entry)
            /\ (DeclaredDynamicWhile(constructor) /\ observed # exit =>
                    observed[1][2] = <<"guard", constructor.loop>>)
            /\ (~DeclaredBodyTransfers(constructor) /\ observed # exit /\
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
        <1>. QED BY ONLY <1>layout, <1>branches DEF DeclaredSequentialConstructorsMatch
        """#
        }
    }
}
