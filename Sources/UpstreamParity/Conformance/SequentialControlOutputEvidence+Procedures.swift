import Foundation
import SwiftTLA

extension SequentialControlOutputEvidence {
    /// Bind control and the skipped assertions of a registered procedure While.
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

        var tables: Set<String> = [pc.formalName]
        var intReads: Set<String> = []
        func formula(_ expression: StateExpr) -> String? {
            func binary(_ left: StateExpr, _ op: String, _ right: StateExpr) -> String? {
                guard let a = formula(left), let b = formula(right) else { return nil }
                return "(\(a) \(op) \(b))"
            }
            switch expression {
            case .variable(let root):
                let matches = program.layout.variables.filter { $0.declaration.name.utf8.elementsEqual(root.utf8) }
                guard matches.count == 1, let variable = matches.first else { return nil }
                let name = variable.formalName
                let local = source.localRoots.contains(root)
                if local { tables.insert(name) }
                let read = local ? "\(name)[worker]" : name
                intReads.insert(read)
                return read
            case .value(.int(let value)):
                return TLAValue.int(value).description
            case .equal(let a, let b):
                return binary(a, "=", b)
            case .greaterThan(let a, let b):
                return binary(a, ">", b)
            case .lessThan(let a, let b):
                return binary(a, "<", b)
            case .and(let a, let b):
                guard let left = formula(a), let right = formula(b) else { return nil }
                return "(IF \(left) THEN \(right) ELSE FALSE)"
            default:
                return nil
            }
        }
        guard let condition = formula(source.condition) else { return nil }

        let checks = String(cfg.dropLast()).components(separatedBy: "\n")
        let directives = Array(checks.dropFirst(2))
        let invariants = directives.compactMap { line -> String? in
            guard line.hasPrefix("INVARIANT ") else { return nil }
            let name = String(line.dropFirst("INVARIANT ".count))
            return rendered.invariantNames.contains(name) || rendered.intrinsicInvariantNames.contains(name) ? name : nil
        }
        let assertions = invariants.filter { $0.hasPrefix("__pcal_assert_") }
        guard cfg.hasSuffix("\n"), checks.prefix(2).elementsEqual(["SPECIFICATION Spec", "CHECK_DEADLOCK TRUE"]),
              invariants.count == directives.count, Set(invariants).count == invariants.count else { return nil }
        let frame = program.layout.variables.filter { $0.id != pc.id }.map(\.formalName)
        let assumed = (tables.sorted().map { #"worker \in DOMAIN \#($0)"# }
                       + intReads.sorted().map { #"\#($0) \in Int"# }).joined(separator: #" /\ "#)
        let workerValues = rows.map { $0.arguments[0].description }
        let pcName = pc.formalName
        let trueArm = source.fallsThrough ? #"""
            /\ ((\#(action)(worker) /\ AuthoredProcedureLoopGuard(worker)) =>
                \#(pcName)' = [\#(pcName) EXCEPT ![worker] = AuthoredProcedureLoopEntry])
        """# : ""
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
        let actionMembers = workerValues.map { #"/\ (\#(action)(\#($0)) => Next)"# }.joined(separator: "\n    ")
        let actionDefinitions = rows.map(\.renderedName).joined(separator: ", ")
        let pages = (1...((cfg.utf8.count + 15) / 16)).map { "CallerInputPage\($0)" }.joined(separator: " ")
        let bytes = TLAValue.tuple(cfg.utf8.map { .int(Int($0)) })
        let slot = source.slot + 1
        let name = "SwiftTLA" + module.name + "ConfiguredProcedureLoopProof"
        let proof = #"""
        ---- MODULE \#(name) ----
        EXTENDS \#(module.name), TLAPS, CallerInputPageBlock1

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

        \#(assertionSource)

        AuthoredProcedureLoopInNext ==
            \#(actionMembers)
        THEOREM ActualNextIncludesTheSelectedProcedureLoop ==
            AuthoredProcedureLoopInNext
            BY ONLY PTL DEF AuthoredProcedureLoopInNext, Next, \#(actionDefinitions)

        \* \#(pages)
        ProcedureLoopActualCFG == [i \in 1..CallerInputSize |-> CallerInputByte[i - 1]]
        ProcedureLoopExpectedCFG == \#(bytes)
        THEOREM ActualProcedureLoopConfigurationIsSelected ==
            ProcedureLoopActualCFG = ProcedureLoopExpectedCFG
        PROOF
        <1>domain. DOMAIN ProcedureLoopActualCFG = DOMAIN ProcedureLoopExpectedCFG
            BY ONLY SMT DEF ProcedureLoopActualCFG, ProcedureLoopExpectedCFG, CallerInputSize
        <1>bytes. \A i \in DOMAIN ProcedureLoopExpectedCFG : ProcedureLoopActualCFG[i] = ProcedureLoopExpectedCFG[i]
            BY ONLY CallerInputPageBlock1AtFileOffsets, SMT DEF ProcedureLoopActualCFG, ProcedureLoopExpectedCFG, CallerInputSize
        <1>. QED BY ONLY <1>domain, <1>bytes, SMT DEF ProcedureLoopActualCFG, ProcedureLoopExpectedCFG

        THEOREM ConfiguredProcedureControlUsesTheAuthoredPaths ==
            /\ ProcedureLoopActualCFG = ProcedureLoopExpectedCFG
            /\ AuthoredProcedureLoopInNext
            /\ (\A worker : AuthoredProcedureLoopInput(worker) => AuthoredProcedureLoopControl(worker))
        \#(assertionResult)
            BY ONLY ActualProcedureLoopConfigurationIsSelected, ActualNextIncludesTheSelectedProcedureLoop,
                ActualProcedureWhileUsesTheAuthoredControl\#(assertionFact), Zenon

        ====

        """#
        return (name, Data(proof.utf8))
    }
}
