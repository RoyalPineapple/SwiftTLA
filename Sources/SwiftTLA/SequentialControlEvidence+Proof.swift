extension SequentialControlEvidence {
    /// The exporter receives the already retained backend inputs, including action metadata used by the real renderer.
    package func proofSource(for rendered: RenderedSpecification, layout: CompiledLayout,
                             physicalAuthored: Machine) throws -> String? {
        let module = rendered.tlaBundle.root.name
        let actions = rendered.actions
        let counters = layout.variables.filter { $0.declaration.origin == .programCounter }
        guard isTLADeclarationName(module), counters.count == 1, let counter = counters.first?.formalName,
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
                $0.owner == reference.owner && $0.sourceName == reference.sourceName
            }
            guard matches.count == 1, let match = matches.first else { return nil }
            return try CompiledValue.controlLocation(match.id).rendered(using: layout).description
        }

        var routeStatements: [String] = []
        var allowedSteps: [String] = []
        var nativeEntries: [String] = []
        var nativeWrites: [String] = []
        for (action, declared) in zip(actions, physicalAuthored.actions) {
            var routes: [String] = []
            var entries: Set<String> = []
            var writes: Set<String> = []
            for branch in declared.branches {
                guard case .guardValue(.equal(.programCounter, .controlLocation(let entry)))? = branch.observations.first,
                      let initial = try formal(entry) else { return nil }
                entries.insert(initial)
                switch branch.control {
                case .transfer(let location):
                    guard let end = try formal(location) else { return nil }
                    routes.append("(\(counter) = \(initial) /\\ \(counter)' = \(end))")
                    writes.insert("<<\"control\", \(end)>>")
                case .unchanged:
                    routes.append("(\(counter) = \(initial) /\\ UNCHANGED \(counter))")
                    writes.insert("<<\"state\", \(TLAValue.string(counter))>>")
                }
            }
            let effect = routes.isEmpty ? "FALSE" : routes.joined(separator: " \\/ ")
            routeStatements.append("/\\ (\(action.renderedName) => (\(effect)))")
            allowedSteps.append("(\(effect))")
            nativeEntries.append("{\(entries.sorted().joined(separator: ", "))}")
            nativeWrites.append("{\(writes.sorted().joined(separator: ", "))}")
        }
        let labels = TLAValue.tuple(actions.map { .string($0.sourceName) })
        let declarations = actions.map(\.renderedName).joined(separator: ", ")
        let next = actions.map(\.renderedName).joined(separator: " \\/ ")
        return #"""
        ---- MODULE SwiftTLASequentialControlProof ----
        EXTENDS \#(module), TLAPS, SwiftTLANativeActions

        PhysicalAuthoredSequentialTrace == \#(physicalTerms)
        CompilerAuthoredSequentialTrace == \#(compilerTerms)
        ScheduledSequentialSemantics == \#(scheduledTerms)
        LoweredSequentialSemantics == \#(loweredTerms)
        ScheduledSequentialTrace == \#(scheduledRoutes)
        LoweredSequentialTrace == \#(loweredRoutes)
        SequentialActionLabels == \#(labels)
        SequentialControlEntries == <<\#(nativeEntries.joined(separator: ", "))>>
        SequentialControlWrites == <<\#(nativeWrites.joined(separator: ", "))>>
        AuthoredSequentialLabels == [index \in DOMAIN PhysicalAuthoredSequentialTrace[2] |-> PhysicalAuthoredSequentialTrace[2][index][1]]
        AuthoredSequentialStep == \#(allowedSteps.joined(separator: " \\/ "))

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

        THEOREM ActualBackendsPreserveSequentialActionInventory ==
            /\ DOMAIN SequentialActionLabels = DOMAIN LoweredSequentialTrace[2]
            /\ \A index \in DOMAIN SequentialActionLabels :
                   SequentialActionLabels[index] = LoweredSequentialTrace[2][index][1]
            /\ DOMAIN NativeActionRows = DOMAIN SequentialActionLabels
            /\ \A index \in DOMAIN NativeActionRows : NativeActionRows[index][1] = SequentialActionLabels[index]
            /\ (Next <=> (\#(next)))
            BY ONLY SMT DEF NativeActionRows, SequentialActionLabels, LoweredSequentialTrace, Next

        THEOREM ActualTLAControlTransfersFollowSelectedRoutes ==
            \#(routeStatements.joined(separator: "\n    "))
            BY ONLY SMT DEF \#(declarations)

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
            BY ONLY SMT DEF NativeControlUsesAuthoredRoutes, NativeActionRows, SequentialControlEntries, SequentialControlWrites

        THEOREM ActualSequentialStepUsesAuthoredRoutes ==
            /\ (Next => AuthoredSequentialStep)
            /\ DOMAIN NativeActionRows = DOMAIN AuthoredSequentialLabels
            /\ \A index \in DOMAIN NativeActionRows : NativeActionRows[index][1] = AuthoredSequentialLabels[index]
            /\ NativeControlUsesAuthoredRoutes
        PROOF
        <1>labels. /\ DOMAIN NativeActionRows = DOMAIN AuthoredSequentialLabels
                   /\ \A index \in DOMAIN NativeActionRows : NativeActionRows[index][1] = AuthoredSequentialLabels[index]
            BY ONLY ActualLoweredControlPreservesAuthoredRouteShape, ActualBackendsPreserveSequentialActionInventory, SMT
                DEF AuthoredSequentialLabels, ScheduledSequentialSemantics, ScheduledSequentialTrace
        <1>routes. Next => AuthoredSequentialStep
            BY ONLY ActualBackendsPreserveSequentialActionInventory, ActualTLAControlTransfersFollowSelectedRoutes, SMT
                DEF AuthoredSequentialStep
        <1>. QED BY ONLY <1>labels, <1>routes, ActualNativeControlTransfersUseSelectedTargets

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
