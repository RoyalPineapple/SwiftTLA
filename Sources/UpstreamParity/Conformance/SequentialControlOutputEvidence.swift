import Foundation
import SwiftTLA

package enum SequentialControlOutputEvidence {
    package struct Proofs: Sendable {
        package let controlModule: String
        package let control: Data
        package let configuredModule: String
        package let configured: Data
    }

    package static func proof(authoredSource: Data, modelName: String, spec: TLASpec,
                              rendered: RenderedSpecification,
                              native: (members: Data, operations: Data, checking: Data)? = nil) throws -> Proofs? {
        guard !authoredSource.contains(0), let text = String(data: authoredSource, encoding: .utf8) else { return nil }
        let source = try AuthoredCopySyntax.select(source: text, modelName: modelName)
        let authored = try AuthoredCopySyntax.controlFrontend(source)
        let (compilation, evidence) = try spec.compileRetainingSequentialControl()
        let actual = rendered.tlaBundle.root
        let entryTypes = SequentialControlEvidence.successfulEntryTypes(in: compilation.layout)
        let program = try native.map { _ in
            let invalid = InitialFailureEvidenceError.unsupportedGeneratedOutput
            guard entryTypes != nil else { throw invalid }
            let types = try CompiledTypeInputs(compilation: compilation,
                types: CompiledTypeContext(enums: .init(), formalNames: [:])) { spelling in
                    guard ["Int", "Swift.Int"].contains(spelling) else { throw invalid }
                    return .int
                }
            return try CompiledProgram(inputs: types)
        }
        guard case .compiled(let identity, _, _) = rendered.tlaBundle.provenance,
              identity == compilation.identity, rendered.tlaBundle.imports.isEmpty,
              let cfg = actual.cfg else { return nil }
        if let program {
            let checked = try program.renderModule()
            guard checked.imports.isEmpty, checked.renderedActions == rendered.actions,
                  actual.name == checked.moduleName, actual.tla.utf8.elementsEqual(checked.renderedModuleSource.utf8),
                  try cfg.utf8.elementsEqual(checked.configuration.render(usesSymmetryReduction: false).utf8)
            else { return nil }
        } else {
            let checked = try compilation.render()
            guard checked.tlaBundle.imports.isEmpty, checked.actions == rendered.actions,
                  actual.name == checked.tlaBundle.root.name,
                  actual.tla.utf8.elementsEqual(checked.tlaBundle.root.tla.utf8),
                  let compiledCFG = checked.tlaBundle.root.cfg, cfg.utf8.elementsEqual(compiledCFG.utf8)
            else { return nil }
        }

        let invariants = rendered.intrinsicInvariantNames
        let prefix = "__SwiftTLAEvaluationOK"
        guard invariants.count <= 1, invariants.allSatisfy({
            $0.hasPrefix(prefix) && $0.dropFirst(prefix.count).allSatisfy { $0 == "_" }
        }) else { return nil }
        let directives = ["SPECIFICATION Spec", "CHECK_DEADLOCK TRUE"]
            + invariants.sorted().map { "INVARIANT \($0)" }
        guard cfg.utf8.elementsEqual((directives.joined(separator: "\n") + "\n").utf8) else { return nil }

        let controlModule = "SwiftTLASequentialControl" + actual.name
        let nativeProof = try native.map { input in
            let invalid = InitialFailureEvidenceError.unsupportedGeneratedOutput
            guard let program, let members = String(data: input.members, encoding: .utf8),
                  let operations = String(data: input.operations, encoding: .utf8),
                  let checking = String(data: input.checking, encoding: .utf8) else { throw invalid }
            try verifyConditionalHistoryHelpers(operations: operations, checking: checking)
            return try sequentialNativeProof(members, program: program)
        }
        guard let control = try evidence?.proofSource(for: rendered, layout: compilation.layout,
            physicalAuthored: authored.machine, proofModule: controlModule, includeNative: false,
            declared: authored.declared, entryTypes: entryTypes) else { return nil }
        let tlaFailureHistory = try program.flatMap {
            try authoredFailureHistory(in: actual.tla, program: $0, authored: authored.machine)
        }
        let configuredModule = controlModule + "ConfiguredProof"
        let cfgBytes = Array(cfg.utf8)
        let cfgPages = stride(from: 0, to: cfgBytes.count, by: 16).enumerated().map { index, offset in
            let end = min(offset + 16, cfgBytes.count)
            let page = "SequentialCFGPage\(index + 1)"
            let fact = "page\(index + 1)"
            let bytes = TLAValue.tuple(cfgBytes[offset..<end].map { .int(Int($0)) })
            let start = offset + 1
            let block = "CallerInputPageBlock\(index / 64 + 1)"
            let statement = #"""
                <2>\#(fact). CASE i \in \#(start)..\#(end)
                    <3>actual. CallerInputByte[i - 1] = \#(page)[i - \#(offset)]
                        BY ONLY <2>\#(fact), \#(block)AtFileOffsets, SMT DEF \#(page)
                    <3>expected. SequentialNormalCFGByte(i) = \#(page)[i - \#(offset)]
                        BY ONLY <2>\#(fact), SMT DEF SequentialNormalCFGByte
                    <3>. QED BY ONLY <3>actual, <3>expected
            """#
            return (request: "CallerInputPage\(index + 1)", definition: "LOCAL \(page) == \(bytes)",
                    selector: #"i \in \#(start)..\#(end) -> \#(page)[i - \#(offset)]"#,
                    proof: statement, fact: "<2>\(fact)")
        }
        let pageModules = (1...((cfgPages.count + 63) / 64)).map { "CallerInputPageBlock\($0)" }.joined(separator: ", ")
        let pages = cfgPages.map(\.request).joined(separator: " ")
        let cfgPageDefinitions = cfgPages.map(\.definition).joined(separator: "\n")
        let cfgSelectors = cfgPages.map(\.selector).joined(separator: " [] ")
        let cfgPageProofs = cfgPages.map(\.proof).joined(separator: "\n")
        let cfgPageFacts = cfgPages.map(\.fact).joined(separator: ", ")
        let authoredInitialFrame: String? = authored.literalInitials.flatMap { bindings in
            let fields = compilation.layout.variables.filter { $0.declaration.origin == .source }
            guard fields.count == bindings.count else { return nil }
            let equalities = fields.compactMap { field -> String? in
                let matches = bindings.filter { $0.name.utf8.elementsEqual(field.declaration.name.utf8) }
                guard matches.count == 1, let binding = matches.first else { return nil }
                return "(\(field.formalName) = \(binding.value))"
            }
            guard equalities.count == fields.count else { return nil }
            return equalities.isEmpty ? "TRUE" : equalities.joined(separator: " /\\ ")
        }
        let initialConverse = #"AuthoredSequentialInitialBindings => (Init <=> AuthoredSequentialInitialControl)"#
        let initialDefinition = authoredInitialFrame.map { "AuthoredSequentialInitialBindings == \($0)" } ?? ""
        let initialConclusion = authoredInitialFrame.map { _ in "/\\ (\(initialConverse))" } ?? ""
        let initialStep = authoredInitialFrame.map { _ in
            """
            <1>initial. \(initialConverse)
                BY ONLY SMT DEF Init, AuthoredSequentialInitialBindings, AuthoredSequentialInitialControl
            """
        } ?? ""
        let initialFact = authoredInitialFrame.map { _ in ", <1>initial" } ?? ""
        let typedInitProof = authoredInitialFrame.map { _ in #"""
        <1>typedInit. Init => AuthoredSequentialTypedEntry
            <2>bindings. Init => AuthoredSequentialInitialBindings
                BY ONLY SMT DEF Init, AuthoredSequentialInitialBindings
            <2>types. AuthoredSequentialInitialBindings => AuthoredSequentialTypedEntry
                BY ONLY SMT DEF AuthoredSequentialInitialBindings, AuthoredSequentialTypedEntry, AuthoredSequentialMachineInts
            <2>. QED BY ONLY <2>bindings, <2>types, PTL
        """# } ?? #"""
        <1>typedInit. Init => AuthoredSequentialTypedEntry
            BY ONLY SMT DEF Init, AuthoredSequentialTypedEntry, AuthoredSequentialMachineInts
        """#
        let typedConclusions = entryTypes == nil ? "" : #"""
        /\ (Spec => []AuthoredSequentialTypedEntry)
            /\ (Spec => [][AuthoredSequentialSuccessfulStep]_vars)
        """#
        let typedFacts = entryTypes == nil ? "" : ", <1>alwaysTyped, <1>successfulSpec"
        let typedSteps = entryTypes == nil ? "" : #"""
        \#(typedInitProof)
        <1>typedNext. AuthoredSequentialTypedEntry /\ Next => AuthoredSequentialTypedEntry'
            BY ONLY AuthoredSequentialSuccessIsExactlyTheEmittedStep, AuthoredSequentialSuccessPreservesTypedEntry, PTL
        <1>typedStutter. AuthoredSequentialTypedEntry /\ UNCHANGED vars => AuthoredSequentialTypedEntry'
            BY ONLY SMT DEF vars, AuthoredSequentialTypedEntry, AuthoredSequentialMachineInts
        <1>induction. AuthoredSequentialTypedEntry /\ [Next]_vars => AuthoredSequentialTypedEntry'
            BY ONLY <1>typedNext, <1>typedStutter, PTL
        <1>alwaysTyped. Spec => []AuthoredSequentialTypedEntry
            <2>initial. Spec => AuthoredSequentialTypedEntry
                BY ONLY <1>typedInit, PTL DEF Spec
            <2>next. Spec => [][Next]_vars
                BY ONLY PTL DEF Spec, vars
            <2>invariant. AuthoredSequentialTypedEntry /\ [][Next]_vars => []AuthoredSequentialTypedEntry
                BY ONLY <1>induction, PTL
            <2>. QED BY ONLY <2>initial, <2>next, <2>invariant, PTL
        <1>step. AuthoredSequentialTypedEntry /\ [Next]_vars => [AuthoredSequentialSuccessfulStep]_vars
            BY ONLY AuthoredSequentialSuccessIsExactlyTheEmittedStep, PTL
        <1>successfulSpec. Spec => [][AuthoredSequentialSuccessfulStep]_vars
            BY ONLY <1>alwaysTyped, <1>step, PTL DEF Spec, vars
        """#
        let comparesBehaviors = authoredInitialFrame != nil && entryTypes != nil
            && source.hasPlainBehavior && compilation.semantics.behavior.fairness.isEmpty
        let behaviorDefinition = comparesBehaviors ? #"AuthoredSequentialBehavior == AuthoredSequentialInitialBindings /\ AuthoredSequentialInitialControl /\ [][AuthoredSequentialSuccessfulStep]_vars"# : ""
        let behaviorConclusion = comparesBehaviors ? #"/\ (Spec <=> AuthoredSequentialBehavior)"# : ""
        let behaviorFact = comparesBehaviors ? ", <1>sameBehavior" : ""
        let behaviorSteps = comparesBehaviors ? #"""
        <1>initialFrame. Init <=> (AuthoredSequentialInitialBindings /\ AuthoredSequentialInitialControl)
            BY ONLY SMT DEF Init, AuthoredSequentialInitialBindings, AuthoredSequentialInitialControl
        <1>sourceTypes. AuthoredSequentialBehavior => []AuthoredSequentialTypedEntry
            <2>entry. AuthoredSequentialInitialBindings => AuthoredSequentialTypedEntry
                BY ONLY SMT DEF AuthoredSequentialInitialBindings, AuthoredSequentialTypedEntry, AuthoredSequentialMachineInts
            <2>preserve. AuthoredSequentialTypedEntry /\ [AuthoredSequentialSuccessfulStep]_vars => AuthoredSequentialTypedEntry'
                BY ONLY AuthoredSequentialSuccessPreservesTypedEntry, <1>typedStutter, PTL
            <2>. QED BY ONLY <2>entry, <2>preserve, PTL DEF AuthoredSequentialBehavior
        <1>emittedStep. AuthoredSequentialTypedEntry /\ [AuthoredSequentialSuccessfulStep]_vars => [Next]_vars
            BY ONLY AuthoredSequentialSuccessIsExactlyTheEmittedStep, PTL
        <1>sameBehavior. Spec <=> AuthoredSequentialBehavior
            BY ONLY <1>initialFrame, <1>successfulSpec, <1>sourceTypes, <1>emittedStep, PTL DEF Spec, vars, AuthoredSequentialBehavior
        """# : ""
        let nativeConclusion = nativeProof == nil ? "" : #"""
        /\ (AuthoredSequentialTypedEntry =>
                \A label : NativeSequentialLabeledStep(label) <=> TLASequentialLabeledStep(label))
            /\ (AuthoredSequentialTypedEntry =>
                \A label : NativeSequentialLabeledFailures(label) = AuthoredSequentialFirstFailure(label))
        """#
        let nativeFact = nativeProof == nil ? "" :
            ", NativeSequentialDispatchUsesEmittedLabeledSteps, NativeSequentialDispatchUsesAuthoredFailures"
        let selection = TLAValue.tuple(invariants.sorted().map(TLAValue.string))
        let failurePrefix = "__SwiftTLAAnyEvaluationFailure"
        let aggregateFailureNames = actual.tla.split(separator: "\n").compactMap { row -> String? in
            guard let name = row.split(separator: " ", maxSplits: 1).first, name.hasPrefix(failurePrefix),
                  isTLADeclarationName(String(name)) else { return nil }
            return String(name)
        }
        let authoredFailureNames = control.split(separator: "\n").compactMap { row -> String? in
            guard row.hasPrefix("AuthoredSequentialActionFailure"), let name = row.split(separator: " ").first else {
                return nil
            }
            return String(name)
        }
        guard nativeProof == nil || !authoredFailureNames.isEmpty else { return nil }
        let check = authoredFailureNames.isEmpty ? nil : invariants.first
        let failureConclusion = check.map {
            "/\\ (Spec => [](\($0) <=> AuthoredSequentialNoReachedFailure))"
        } ?? ""
        let failureSteps = check.map { check in
            let definitions = ([check, "AuthoredSequentialTypedEntry", "AuthoredSequentialMachineInts",
                "AuthoredSequentialNoReachedFailure"] + aggregateFailureNames + authoredFailureNames).joined(separator: ", ")
            return #"""
            <1>failureCheck. AuthoredSequentialTypedEntry => (\#(check) <=> AuthoredSequentialNoReachedFailure)
                BY ONLY SMT DEF \#(definitions)
            <1>configuredFailures. Spec => [](\#(check) <=> AuthoredSequentialNoReachedFailure)
                BY ONLY <1>alwaysTyped, <1>failureCheck, PTL
            """#
        } ?? ""
        let failureFact = check == nil ? "" : ", <1>configuredFailures"
        let historyConclusion = tlaFailureHistory == nil ? "" : #"""
        /\ (AuthoredSequentialTypedEntry => TLASequentialFailureHistoriesMatch)
        """#
        let historyFact = tlaFailureHistory == nil ? "" : ", TLASequentialHistoryUsesAuthoredFailures"
        let configured = #"""
        ---- MODULE \#(configuredModule) ----
        EXTENDS \#(controlModule), \#(pageModules)

        \* \#(pages)
        SequentialActualCFG == [i \in 1..CallerInputSize |-> CallerInputByte[i - 1]]
        \#(cfgPageDefinitions)
        LOCAL SequentialNormalCFGByte(i) == CASE \#(cfgSelectors) [] OTHER -> 0
        SequentialNormalCFG == [i \in 1..\#(cfgBytes.count) |-> SequentialNormalCFGByte(i)]
        SequentialSelectedEvaluationChecks == \#(selection)
        \#(initialDefinition)
        \#(behaviorDefinition)
        \#(nativeProof?.definitions ?? "")
        \#(nativeProof?.theorem ?? "")
        \#(tlaFailureHistory ?? "")

        THEOREM NormalConfigurationUsesOnlyAuthoredSequentialControl ==
            /\ SequentialActualCFG = SequentialNormalCFG
            /\ (Spec => AuthoredSequentialInitialControl)
            \#(initialConclusion)
            /\ (Spec => [][AuthoredSequentialStep]_vars)
            \#(typedConclusions)
            /\ SequentialSelectedEvaluationChecks = \#(selection)
            \#(failureConclusion)
            \#(historyConclusion)
            \#(behaviorConclusion)
            \#(nativeConclusion)
            /\ (~AuthoredSequentialGuard => ~ENABLED Next)
            /\ (AuthoredSequentialWriteFreeGuard => ENABLED Next)
            /\ PhysicalAuthoredSequentialTrace = LoweredSequentialSemantics
            /\ DeclaredSequentialConstructorsMatch(LoweredSequentialSemantics)
        PROOF
        <1>length. CallerInputSize = \#(cfgBytes.count)
            BY ONLY SMT DEF CallerInputSize
        <1>bytes. \A i \in 1..\#(cfgBytes.count) : CallerInputByte[i - 1] = SequentialNormalCFGByte(i)
            <2>. TAKE i \in 1..\#(cfgBytes.count)
        \#(cfgPageProofs)
            <2>. QED BY ONLY (i \in 1..\#(cfgBytes.count)), \#(cfgPageFacts), SMT
        <1>configuration. SequentialActualCFG = SequentialNormalCFG
            BY ONLY <1>length, <1>bytes, SMT DEF SequentialActualCFG, SequentialNormalCFG
        \#(initialStep)
        \#(typedSteps)
        \#(behaviorSteps)
        \#(failureSteps)
        <1>. QED BY ONLY <1>configuration, ActualSpecUsesOnlyAuthoredSequentialControl,
            ActualLoweredRoutesUseTheDeclaredSequentialConstructors\#(initialFact)\#(typedFacts)\#(nativeFact)\#(failureFact)\#(historyFact)\#(behaviorFact)
            DEF SequentialSelectedEvaluationChecks

        ====

        """#
        return .init(controlModule: controlModule, control: Data(control.utf8),
                     configuredModule: configuredModule, configured: Data(configured.utf8))
    }
    private static func authoredFailureHistory(in tla: String, program: CompiledProgram,
                                               authored: SequentialControlEvidence.Machine) throws -> String? {
        let invalid = InitialFailureEvidenceError.unsupportedGeneratedOutput
        guard let counter = program.layout.variables.first(where: { $0.declaration.origin == .programCounter }) else {
            throw invalid
        }
        let state = "<<\(program.layout.variables.map(\.formalName).joined(separator: ", "))>>"
        var definitions: [String] = []
        var equalities: [String] = []
        var proofs: [String] = []
        var facts: [String] = []
        for action in program.behavior.actions {
            let index = action.id.ordinal
            let base = "__SwiftTLAActionFailureHistory\(index)"
            let names = tla.split(separator: "\n").compactMap { line -> String? in
                guard let separator = line.range(of: " == ") else { return nil }
                let name = line[..<separator.lowerBound]
                guard name.hasPrefix(base), name.dropFirst(base.count).allSatisfy({ $0 == "_" }) else { return nil }
                return String(name)
            }
            let regions = action.body.orderedAlternativeFailureRegions(afterControlGuardOf: counter.id)
            guard names.count == (regions.isEmpty ? 0 : 1) else { throw invalid }
            guard let history = names.first else { continue }
            guard authored.actions.indices.contains(index),
                  authored.actions[index].label.utf8.elementsEqual(program.layout.actions[index].declaration.name.utf8),
                  authored.actions[index].branches.count == regions.count else { throw invalid }
            var failureDefinitions: [String] = []
            var histories: [String] = []
            for (branch, pair) in zip(authored.actions[index].branches, regions).enumerated() {
                let (source, region) = pair
                let targets = source.observations.compactMap { item -> String? in
                    guard case .write(let target, _) = item else { return nil }
                    return target
                }
                let boundTargets = region.bindings.map { program.layout.variables[$0.target.ordinal].declaration.name }
                guard region.armOrdinal == branch, region.sharedBindingCount == 0,
                      targets.elementsEqual(boundTargets, by: { $0.utf8.elementsEqual($1.utf8) }) else { throw invalid }
                guard !targets.isEmpty else { continue }
                let sourceFailure = "AuthoredSequentialActionFailure\(index + 1)Branch\(branch + 1)"
                let result = "TLASequentialAuthoredHistory\(index + 1)Arm\(branch + 1)"
                let slots = "<<\(region.bindings.map {
                    "[binding |-> \($0.binder.ordinal), target |-> \($0.target.ordinal)]"
                }.joined(separator: ", "))>>"
                definitions.append(#"""
                LOCAL \#(result) ==
                    LET history == \#(sourceFailure)
                        slots == \#(slots)
                    IN IF history = <<>> THEN <<>>
                       ELSE LET failure == history[1]
                                site == slots[failure.site]
                            IN <<[source |-> \#(state), action |-> \#(index), branch |-> \#(branch),
                                  site |-> site.binding, target |-> site.target, payload |-> failure.payload,
                                  before |-> [i \in DOMAIN failure.completed |->
                                      [binding |-> slots[i].binding, target |-> slots[i].target,
                                       value |-> failure.completed[i]]]]>>
                """#)
                failureDefinitions += [sourceFailure, result]
                histories.append(result)
            }
            guard !histories.isEmpty else { throw invalid }
            let equality = "\(history) = \(histories.joined(separator: " \\o "))"
            let fact = "<1>action\(index + 1)"
            let defs = ([history, "AuthoredSequentialTypedEntry", "AuthoredSequentialMachineInts"]
                        + failureDefinitions).joined(separator: ", ")
            equalities.append("/\\ (\(equality))")
            proofs.append("""
            \(fact). \(equality)
                BY ONLY AuthoredSequentialTypedEntry, SMT DEF \(defs)
            """)
            facts.append(fact)
        }
        guard !facts.isEmpty else { return nil }
        return #"""
        \#(definitions.joined(separator: "\n"))
        TLASequentialFailureHistoriesMatch == \#(equalities.joined(separator: "\n    "))

        THEOREM TLASequentialHistoryUsesAuthoredFailures ==
            AuthoredSequentialTypedEntry => TLASequentialFailureHistoriesMatch
        PROOF
        <1>. SUFFICES ASSUME AuthoredSequentialTypedEntry PROVE TLASequentialFailureHistoriesMatch BY PTL
        \#(proofs.joined(separator: "\n"))
        <1>. QED BY ONLY \#(facts.joined(separator: ", ")), PTL DEF TLASequentialFailureHistoriesMatch
        """#
    }
}
