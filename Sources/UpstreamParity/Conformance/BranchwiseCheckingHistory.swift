import SwiftTLA

/// The graph IDs and the M8 occurrences come from the same exhaustive visitor.
struct BranchwiseCheckingHistory<Machine: StateMachine> {
    private var snapshots: [TLAValue] = []
    private var snapshotIDs: [Machine.Snapshot: Int] = [:]
    private var initialIDs: Set<TLAValue> = []
    private var edges: Set<TLAValue> = []
    private var callbacks: [(source: Int, action: Int, reason: NativeMachineEvaluationError)] = []
    private var failedClaims: [(Machine.Property, Machine.Snapshot)] = []

    mutating func observe(_ event: MachineValidationEvent<Machine>, machine: Machine,
                          program: CompiledProgram) throws {
        switch event {
        case .state(let id, let snapshot, let initial, _, _):
            let projection = try machine.formalProjection(of: snapshot)
            let fields = program.layout.variables
            guard id == snapshots.count, projection.entries.count == fields.count,
                  snapshotIDs.updateValue(id, forKey: snapshot) == nil else { throw invalidBranchwiseField("native state identity") }
            let values = try fields.map { field -> TLAValue in
                guard let token = TLAStateProjection.Token(validating: field.formalName),
                      let value = projection.value(for: token), case .int = value
                else { throw invalidBranchwiseField("native state projection") }
                return value
            }
            snapshots.append(.tuple(values))
            if initial { initialIDs.insert(.int(id)) }
        case .edge(let source, let action, let target):
            guard snapshots.indices.contains(source), snapshots.indices.contains(target)
            else { throw invalidBranchwiseField("native labeled edge") }
            let ordinal = try actionOrdinal(action, machine: machine, program: program)
            edges.insert(.tuple([.int(source), .int(ordinal), .int(target)]))
        case .evaluationFailure(let source, let action, let reason):
            let ordinal = try actionOrdinal(action, machine: machine, program: program)
            callbacks.append((source, ordinal, reason))
        case .invariantFailure(let property, let snapshot, _, _):
            failedClaims.append((property, snapshot))
        default: break
        }
    }

    func definitions(history: [ValidationActionFailureOccurrence], summary: MachineValidationSummary<Machine.Property>,
                     names: [Machine.Property: String], program: CompiledProgram) throws -> String {
        guard snapshots.count == summary.states, initialIDs.count == summary.initialStates,
              !history.isEmpty, program.layout.actions.count == 1, let action = program.layout.actions.first
        else { throw invalidBranchwiseField("complete branchwise graph and history") }
        guard callbacks.elementsEqual(history, by: { callback, occurrence in
            callback.source == occurrence.source && callback.action == occurrence.failure.action
                && callback.reason == occurrence.failure.reason
        }) else { throw invalidBranchwiseField("ordered history does not match native action callbacks") }
        let occurrences = try history.map { occurrence -> TLAValue in
            guard snapshots.indices.contains(occurrence.source), occurrence.failure.action == action.id.ordinal
            else { throw invalidBranchwiseField("native failure identity") }
            let failure = occurrence.failure
            let payload: TLAValue
            switch failure.reason {
            case .divisionByZero: payload = .tuple([.string("divisionByZero")])
            case .negativeModuloDivisor(let value): payload = .tuple([.string("negativeModuloDivisor"), .int(value)])
            default: throw invalidBranchwiseField("native failure payload")
            }
            let before = failure.before.map { binding in
                branchwiseRecord([("binding", .int(binding.binding)), ("target", .int(binding.target)), ("value", .int(binding.value))])
            }
            let event = branchwiseRecord([
                ("source", snapshots[occurrence.source]), ("action", .int(failure.action)),
                ("branch", .int(failure.branch)), ("site", .int(failure.site)), ("target", .int(failure.target)),
                ("payload", payload), ("before", .tuple(before)),
            ])
            return .tuple([.int(occurrence.source), .int(failure.action), event])
        }
        var cuts = [TLAValue.int(0)]
        var offset = 0
        for id in snapshots.indices {
            while offset < history.count, history[offset].source == id { offset += 1 }
            cuts.append(.int(offset))
        }
        guard offset == history.count else { throw invalidBranchwiseField("native traversal failure ordering") }
        let claimFailures = try failedClaims.map { property, snapshot -> TLAValue in
            guard let name = names[property], let id = snapshotIDs[snapshot] else { throw invalidBranchwiseField("native property observation") }
            return .tuple([.string(name), .int(id)])
        }
        guard Set(failedClaims.map { $0.0 }) == summary.violatedInvariants else { throw invalidBranchwiseField("native property coverage") }
        return """
        BranchwiseNativeSnapshots == \(TLAValue.tuple(snapshots))
        BranchwiseNativeInitialIDs == \(TLAValue.set(initialIDs))
        BranchwiseNativeEdges == \(TLAValue.set(edges))
        BranchwiseNativeHistory == \(TLAValue.tuple(occurrences))
        BranchwiseNativeCuts == \(TLAValue.tuple(cuts))
        BranchwiseNativeClaimFailures == \(TLAValue.set(Set(claimFailures)))
        BranchwiseNativeFields == \(TLAValue.tuple(program.layout.variables.map { .string($0.formalName) }))
        """
    }

    private func actionOrdinal(_ action: Machine.Action, machine: Machine, program: CompiledProgram) throws -> Int {
        let call = try machine.formalCall(for: action)
        let matches = program.layout.actions.filter { $0.renderedName.utf8.elementsEqual(call.name.utf8) }
        guard call.arguments.isEmpty, matches.count == 1, let layout = matches.first
        else { throw invalidBranchwiseField("native action identity") }
        return layout.id.ordinal
    }
}

private func invalidBranchwiseField(_ field: String) -> EvidenceFormatError {
    .invalidField(record: "Branchwise selected checks", field: field)
}

private func branchwiseRecord(_ fields: [(String, TLAValue)]) -> TLAValue {
    .record(TLARecord(fields.map { .init($0.0, $0.1) }))
}

extension CheckingSelectionEvidence {
    package static func branchwiseContinuationDefinitions(
        authoredSource: String,
        receipts: [String: StraightLineAssignmentCheck.AtomicBranchContinuationReceipt],
        program: CompiledProgram, rendered: RenderedModule) throws -> String {
        guard rendered.moduleName.utf8.elementsEqual(program.moduleName.utf8),
              program.layout.actions.count == 1, let action = program.layout.actions.first,
              let receipt = receipts[action.declaration.name], receipt.condition == nil,
              let emitted = rendered.actionCaptureGuards[action.id]
        else { throw invalidBranchwiseField("retained atomic continuation") }
        let authored = try AuthoredCopySyntax.branchwiseAssignments(source: authoredSource, modelName: program.moduleName)
        guard authored.label == .string(action.declaration.name),
              authored.fields == Set(receipt.fields.map(TLAValue.string)),
              authored.prefix.count == receipt.prefix.count, authored.suffix.count == receipt.suffixLength
        else { throw invalidBranchwiseField("uploaded continuation source") }
        let prefixCount = authored.prefix.count
        let suffixLength = authored.suffix.count
        let sourcePaths = authored.arms.map { authored.prefix + $0 + authored.suffix }
        var fork = program[action.id].body
        let regions = fork.orderedAlternativeFailureRegions
        guard suffixLength > 0, regions.count == 2 else { throw invalidBranchwiseField("nonempty alternative continuation") }
        let retainedPaths = [receipt.first, receipt.second]
        for (armIndex, pair) in zip(retainedPaths, regions).enumerated() {
            let (retained, region) = pair
            let count = region.bindings.count
            guard region.armOrdinal == armIndex, count >= prefixCount + suffixLength,
                  retained.captures.count == count, retained.sourceCaptures.count == count,
                  retained.targets.count == count, sourcePaths[armIndex].count == count,
                  retained.captures.prefix(prefixCount).elementsEqual(receipt.prefix)
            else { throw invalidBranchwiseField("continuation capture count") }
        }
        for index in 0..<prefixCount {
            let first = regions[0].bindings[index]
            let second = regions[1].bindings[index]
            guard first.binder == second.binder, first.target == second.target,
                  regions[0].index(of: first.binder) == nil, regions[1].index(of: second.binder) == nil,
                  receipt.first.targets[index].utf8.elementsEqual(receipt.second.targets[index].utf8),
                  receipt.first.sourceCaptures[index] == receipt.second.sourceCaptures[index]
            else { throw invalidBranchwiseField("shared continuation capture identity") }
        }

        let fields = program.layout.variables
        let fieldRoots = Dictionary(uniqueKeysWithValues: fields.map { ($0.id, $0.declaration.name) })
        let statePositions = Dictionary(uniqueKeysWithValues: fields.enumerated().map { ($0.element.id, $0.offset + 1) })
        guard receipt.fields == Set(fieldRoots.values) else { throw invalidBranchwiseField("continuation state roots") }

        var captures: [TLAValue: TLAValue] = [:]
        var paths: [TLAValue] = []
        var guardedPaths: [String] = []
        var names = Set(fields.map(\.formalName) + emitted.values.map(\.name))
        func fresh(_ base: String) -> String {
            var name = base
            while !names.insert(name).inserted { name += "_" }
            return name
        }
        let snapshot = fresh("ContinuationSnapshot")
        let arm = fresh("ContinuationArm")
        let position = fresh("ContinuationPosition")
        struct CapturePath {
            var bindings: [TLAValue] = []
            var rows: [TLAValue] = []
            var positions: [BinderID: Int] = [:]
            var latestWriter: [VariableID: Int] = [:]
        }
        func readCaptures(
            _ range: Range<Int>, in body: inout CompiledActionExpr, path: inout CapturePath,
            retained: StraightLineAssignmentCheck.AtomicBranchContinuationReceipt.Branch,
            region: AlternativeFailureRegion
        ) throws {
            // Compare the compiled scalar references against the independently bound
            // source references, retaining native event sites and snapshot positions.
            func reference(_ expression: CompiledExpression) -> (TLAValue, TLAValue)? {
                guard expression.resultType == .int, expression.children.isEmpty else { return nil }
                switch expression.operation {
                case .value(.integer(let value)):
                    let token = TLAValue.tuple([.string("literal"), .int(value)])
                    return (token, token)
                case .stateVariable(let field):
                    guard let root = fieldRoots[field], let position = statePositions[field] else { return nil }
                    return (.tuple([.string("state"), .string(root)]), .tuple([.string("state"), .int(position)]))
                case .boundValue(let binder):
                    guard let position = path.positions[binder] else { return nil }
                    let token = TLAValue.tuple([.string("capture"), .int(position)])
                    return (token, token)
                default:
                    return nil
                }
            }

            for index in range {
                let origin = region.bindings[index]
                guard case .define(let binder, let value, let next) = body, binder == origin.binder,
                      let root = fieldRoots[origin.target], root.utf8.elementsEqual(retained.targets[index].utf8)
                else { throw invalidBranchwiseField("continuation site and target") }
                let source = sourcePaths[region.armOrdinal][index]
                let original = source.sourceTerm
                guard source.target == .string(root), original == retained.sourceCaptures[index]
                else { throw invalidBranchwiseField("uploaded continuation assignment") }
                let expected = retained.captures[index]
                guard original.count == expected.count else { throw invalidBranchwiseField("continuation source token count") }
                let reads = try zip(original, expected).compactMap { sourceToken, reference -> TLAValue? in
                    guard case .tuple(let token) = sourceToken, let role = token.first
                    else { throw invalidBranchwiseField("continuation source token") }
                    if role != .string("state") {
                        guard sourceToken == reference else { throw invalidBranchwiseField("continuation source constructor") }
                        return nil
                    }
                    guard token.count == 2, case .string(let key) = token[1], receipt.fields.contains(key),
                          case .tuple(let route) = reference, route.count == 2
                    else { throw invalidBranchwiseField("continuation read reference") }
                    switch (route[0], route[1]) {
                    case (.string("state"), .string(let field)) where field.utf8.elementsEqual(key.utf8): break
                    case (.string("capture"), .int(let capture)) where capture > 0 && capture <= index: break
                    default: throw invalidBranchwiseField("continuation read reference")
                    }
                    return branchwiseRecord([("key", .string(key)), ("reference", reference)])
                }
                path.rows.append(branchwiseRecord([
                    ("target", source.target), ("sourceTerm", .tuple(original)), ("reads", .tuple(reads)),
                ]))
                if let (sourceToken, _) = reference(value) {
                    guard expected == [sourceToken] else { throw invalidBranchwiseField("continuation scalar capture") }
                } else {
                    let operation: String
                    switch value.operation {
                    case .divide: operation = "divide"
                    case .modulo: operation = "modulo"
                    default: throw invalidBranchwiseField("continuation failure operation")
                    }
                    guard region.index(of: binder) == index, value.children.count == 2,
                          let (left, physicalLeft) = reference(value.children[0]),
                          let (right, physicalRight) = reference(value.children[1]),
                          expected == [.tuple([.string(operation)]), left, right]
                    else { throw invalidBranchwiseField("continuation operand references") }
                    captures[.int(binder.ordinal)] = branchwiseRecord([
                        ("branch", .int(region.armOrdinal)), ("target", .int(origin.target.ordinal)),
                        ("prior", .tuple(path.bindings)), ("position", .int(index + 1)),
                        ("inSuffix", .bool(index >= region.bindings.count - suffixLength)),
                        ("operation", .string(operation)), ("operands", .tuple([physicalLeft, physicalRight])),
                    ])
                }
                path.bindings.append(.tuple([.int(binder.ordinal), .int(origin.target.ordinal)]))
                path.positions[binder] = index + 1
                path.latestWriter[origin.target] = index + 1
                body = next
            }
        }

        var shared = CapturePath()
        try readCaptures(0..<prefixCount, in: &fork, path: &shared, retained: receipt.first, region: regions[0])
        guard case .or(let first, let second) = fork else { throw invalidBranchwiseField("continuation choice after shared captures") }
        func guardedPrefix(_ region: AlternativeFailureRegion, _ range: Range<Int>, then rest: String) throws -> String {
            try range.reversed().reduce(rest) { later, index in
                guard let capture = emitted[region.bindings[index].binder] else { throw invalidBranchwiseField("emitted capture guard") }
                let local = "(IF \(position) = \(index + 1) THEN TRUE ELSE "
                    + "(LET \(capture.name) == \(capture.value) IN \(later)))"
                return capture.condition.map { "(IF \($0) THEN \(local) ELSE FALSE)" } ?? local
            }
        }
        var commonFrame = Set(statePositions.values)
        for (region, initialBody) in zip(regions, [first, second]) {
            let retained = retainedPaths[region.armOrdinal]
            let local = prefixCount..<region.bindings.count
            let writes = try Dictionary(retained.writes.map { ($0.root, $0.reference) },
                uniquingKeysWith: { _, _ in throw invalidBranchwiseField("duplicate retained write") })
            guard Set(writes.keys) == receipt.fields else { throw invalidBranchwiseField("continuation frame coverage") }

            var path = CapturePath(positions: shared.positions, latestWriter: shared.latestWriter)
            var body = initialBody
            try readCaptures(local, in: &body, path: &path, retained: retained, region: region)

            var pending = [body]
            var unchanged: Set<Int> = []
            var assigned: Set<Int> = []
            while let item = pending.popLast() {
                switch item {
                case .and(let lhs, let rhs):
                    pending.append(lhs)
                    pending.append(rhs)
                case .unchanged(let field):
                    guard let root = fieldRoots[field], let position = statePositions[field],
                          path.latestWriter[field] == nil, writes[root] == .tuple([.string("state"), .string(root)])
                    else { throw invalidBranchwiseField("continuation unchanged field") }
                    guard unchanged.insert(position).inserted else { throw invalidBranchwiseField("duplicate unchanged field") }
                case .assign(let target, let value):
                    guard let root = fieldRoots[target], let position = statePositions[target],
                          case .boundValue(let binder) = value.operation, let capture = path.positions[binder],
                          path.latestWriter[target] == capture, writes[root] == .tuple([.string("capture"), .int(capture)]),
                          assigned.insert(position).inserted
                    else { throw invalidBranchwiseField("continuation final write") }
                case .guard_: break // Truth of an unbound guard is checked by orderedAlternativeFailureRegions.
                default: throw invalidBranchwiseField("continuation frame shape")
                }
            }
            guard unchanged.isDisjoint(with: assigned), unchanged.union(assigned) == Set(statePositions.values)
            else { throw invalidBranchwiseField("continuation frame coverage") }
            commonFrame.formIntersection(unchanged)
            paths.append(.tuple(path.rows))
            let guarded = try guardedPrefix(region, local, then: "FALSE")
            guardedPaths.append("\(arm) = \(region.armOrdinal) -> \(guarded)")
        }

        let bound = fields.enumerated().map {
            "\($0.element.formalName) == \(snapshot)[\($0.offset + 1)]"
        }.joined(separator: " ")
        let cases = "CASE \(guardedPaths.joined(separator: " [] ")) [] OTHER -> FALSE"
        let guards = try guardedPrefix(regions[0], 0..<prefixCount, then: cases)
        let invocationPaths: String
        if prefixCount == 0 {
            invocationPaths = """
            BranchwiseContinuationPaths == \(TLAValue.tuple(paths))
            BranchwiseContinuationArms == BranchwiseContinuationPaths
            """
        } else {
            invocationPaths = #"""
            BranchwiseContinuationArms == \#(TLAValue.tuple(paths))
            BranchwiseContinuationPaths ==
                [arm \in DOMAIN BranchwiseContinuationArms |->
                    BranchwiseContinuationPrefix \o BranchwiseContinuationArms[arm]]
            """#
        }
        return """
        BranchwisePhysicalCaptureGuard(\(snapshot), \(arm), \(position)) ==
            LET \(bound) IN \(guards)
        BranchwiseScheduledAction == \(action.id.ordinal)
        BranchwiseScheduledPrefixBindings == \(TLAValue.tuple(shared.bindings))
        BranchwiseContinuationPrefix == \(TLAValue.tuple(shared.rows))
        \(invocationPaths)
        BranchwiseContinuationKeys == \(TLAValue.set(Set(receipt.fields.map(TLAValue.string))))
        BranchwiseContinuationPrefixLength == \(receipt.prefix.count)
        BranchwiseContinuationSuffixLength == \(suffixLength)
        BranchwiseScheduledFailures == \(TLAValue.function(captures))
        BranchwiseScheduledFrame == \(TLAValue.set(Set(commonFrame.map(TLAValue.int))))
        """
    }
}
