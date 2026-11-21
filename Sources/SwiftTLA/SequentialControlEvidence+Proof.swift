extension SequentialControlEvidence {
    /// The exporter receives the already retained backend inputs, including action metadata used by the real renderer.
    package func proofSource(for rendered: RenderedSpecification, layout: CompiledLayout) throws -> String? {
        let module = rendered.tlaBundle.root.name
        let actions = rendered.actions
        let counters = layout.variables.filter { $0.declaration.origin == .programCounter }
        guard isTLADeclarationName(module), counters.count == 1, let counter = counters.first?.formalName,
              isTLADeclarationName(counter), !actions.isEmpty,
              actions.allSatisfy({ $0.arguments.isEmpty && isTLADeclarationName($0.renderedName) }) else { return nil }

        func location(_ value: ControlLocationReference) -> TLAValue {
            .tuple([.string(value.owner?.canonicalEncoding ?? ""), .string(value.sourceName)])
        }
        func control(_ value: Control) -> TLAValue {
            switch value {
            case .transfer(let destination): .tuple([.string("transfer"), location(destination)])
            case .unchanged: .tuple([.string("unchanged")])
            }
        }
        func table(_ machine: Machine, observations: (Branch) -> TLAValue) -> TLAValue {
            .tuple([location(machine.initial), .tuple(machine.actions.map { action in
                .tuple([.string(action.label), .tuple(action.branches.map {
                    .tuple([observations($0), control($0.control)])
                })])
            })])
        }
        func shape(_ branch: Branch) -> TLAValue {
            .tuple(branch.observations.compactMap { observation in
                guard case .guardValue(let expression) = observation else { return nil }
                if case .not = expression { return .string("negated") }
                return .string("guard")
            })
        }
        var expressions: [StateExpr: Int] = [:]
        func index(_ expression: StateExpr) -> TLAValue {
            if let existing = expressions[expression] { return .int(existing) }
            let next = expressions.count + 1
            expressions[expression] = next
            return .int(next)
        }
        func trace(_ branch: Branch) -> TLAValue {
            .tuple(branch.observations.map { observation in
                switch observation {
                case .guardValue(let expression): .tuple([.string("guard"), index(expression)])
                case .capture(let name, let expression): .tuple([.string("capture"), .string(name), index(expression)])
                }
            })
        }
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
        for (action, declared) in zip(actions, authored.actions) {
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

        AuthoredSequentialShape == \#(table(authored, observations: shape))
        ScheduledSequentialShape == \#(table(scheduled, observations: shape))
        ScheduledSequentialTrace == \#(table(scheduled, observations: trace))
        LoweredSequentialTrace == \#(table(lowered, observations: trace))
        SequentialActionLabels == \#(labels)
        SequentialControlEntries == <<\#(nativeEntries.joined(separator: ", "))>>
        SequentialControlWrites == <<\#(nativeWrites.joined(separator: ", "))>>
        AuthoredSequentialLabels == [index \in DOMAIN AuthoredSequentialShape[2] |-> AuthoredSequentialShape[2][index][1]]
        AuthoredSequentialStep == \#(allowedSteps.joined(separator: " \\/ "))

        THEOREM ActualLoweredControlPreservesAuthoredRouteShape ==
            /\ AuthoredSequentialShape = ScheduledSequentialShape
            /\ ScheduledSequentialTrace = LoweredSequentialTrace
            BY ONLY SMT DEF AuthoredSequentialShape, ScheduledSequentialShape,
                ScheduledSequentialTrace, LoweredSequentialTrace

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
                DEF AuthoredSequentialLabels, ScheduledSequentialShape, ScheduledSequentialTrace
        <1>routes. Next => AuthoredSequentialStep
            BY ONLY ActualBackendsPreserveSequentialActionInventory, ActualTLAControlTransfersFollowSelectedRoutes, SMT
                DEF AuthoredSequentialStep
        <1>. QED BY ONLY <1>labels, <1>routes, ActualNativeControlTransfersUseSelectedTargets

        ====

        """#
    }
}
