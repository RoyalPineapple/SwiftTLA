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
                  snapshotIDs.updateValue(id, forKey: snapshot) == nil else { throw invalid("native state identity") }
            let values = try fields.map { field -> TLAValue in
                guard let token = TLAStateProjection.Token(validating: field.formalName),
                      let value = projection.value(for: token), case .int = value
                else { throw invalid("native state projection") }
                return value
            }
            snapshots.append(.tuple(values))
            if initial { initialIDs.insert(.int(id)) }
        case .edge(let source, let action, let target):
            guard snapshots.indices.contains(source), snapshots.indices.contains(target)
            else { throw invalid("native labeled edge") }
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
        else { throw invalid("complete branchwise graph and history") }
        guard callbacks.elementsEqual(history, by: { callback, occurrence in
            callback.source == occurrence.source && callback.action == occurrence.failure.action
                && callback.reason == occurrence.failure.reason
        }) else { throw invalid("ordered history does not match native action callbacks") }
        let occurrences = try history.map { occurrence -> TLAValue in
            guard snapshots.indices.contains(occurrence.source), occurrence.failure.action == action.id.ordinal
            else { throw invalid("native failure identity") }
            let failure = occurrence.failure
            let payload: TLAValue
            switch failure.reason {
            case .divisionByZero: payload = .tuple([.string("divisionByZero")])
            case .negativeModuloDivisor(let value): payload = .tuple([.string("negativeModuloDivisor"), .int(value)])
            default: throw invalid("native failure payload")
            }
            let before = failure.before.map { binding in
                record([("binding", .int(binding.binding)), ("target", .int(binding.target)), ("value", .int(binding.value))])
            }
            let event = record([
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
        guard offset == history.count else { throw invalid("native traversal failure ordering") }
        let claimFailures = try failedClaims.map { property, snapshot -> TLAValue in
            guard let name = names[property], let id = snapshotIDs[snapshot] else { throw invalid("native property observation") }
            return .tuple([.string(name), .int(id)])
        }
        guard Set(failedClaims.map { $0.0 }) == summary.violatedInvariants else { throw invalid("native property coverage") }
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
        else { throw invalid("native action identity") }
        return layout.id.ordinal
    }

    private func invalid(_ field: String) -> EvidenceFormatError {
        .invalidField(record: "Branchwise selected checks", field: field)
    }

    private func record(_ fields: [(String, TLAValue)]) -> TLAValue {
        .record(TLARecord(fields.map { .init($0.0, $0.1) }))
    }
}
