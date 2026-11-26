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
        let checked = try compilation.render()
        guard case .compiled(let identity, _, _) = rendered.tlaBundle.provenance,
              identity == compilation.identity, rendered.tlaBundle.imports.isEmpty,
              checked.tlaBundle.imports.isEmpty, checked.actions == rendered.actions,
              actual.name == checked.tlaBundle.root.name,
              actual.tla.utf8.elementsEqual(checked.tlaBundle.root.tla.utf8),
              let cfg = actual.cfg, let compiledCFG = checked.tlaBundle.root.cfg,
              cfg.utf8.elementsEqual(compiledCFG.utf8) else { return nil }

        let invariants = rendered.intrinsicInvariantNames
        let prefix = "__SwiftTLAEvaluationOK"
        guard invariants.count <= 1, invariants.allSatisfy({
            $0.hasPrefix(prefix) && $0.dropFirst(prefix.count).allSatisfy { $0 == "_" }
        }) else { return nil }
        let directives = ["SPECIFICATION Spec", "CHECK_DEADLOCK TRUE"]
            + invariants.sorted().map { "INVARIANT \($0)" }
        guard cfg.utf8.elementsEqual((directives.joined(separator: "\n") + "\n").utf8) else { return nil }

        let controlModule = "SwiftTLASequentialControl" + actual.name
        let entryTypes = SequentialControlEvidence.successfulEntryTypes(in: compilation.layout)
        let nativeProof = try native.map { input in
            let invalid = InitialFailureEvidenceError.unsupportedGeneratedOutput
            guard entryTypes != nil,
                  let members = String(data: input.members, encoding: .utf8),
                  let operations = String(data: input.operations, encoding: .utf8),
                  let checking = String(data: input.checking, encoding: .utf8) else { throw invalid }
            try verifyConditionalHistoryHelpers(operations: operations, checking: checking)
            let types = try CompiledTypeInputs(compilation: compilation,
                types: CompiledTypeContext(enums: .init(), formalNames: [:])) { spelling in
                    guard ["Int", "Swift.Int"].contains(spelling) else { throw invalid }
                    return .int
                }
            return try sequentialNativeProof(members, program: CompiledProgram(inputs: types))
        }
        guard let control = try evidence?.proofSource(for: rendered, layout: compilation.layout,
            physicalAuthored: authored.machine, proofModule: controlModule, includeNative: false,
            declared: authored.declared, entryTypes: entryTypes) else { return nil }
        let configuredModule = controlModule + "ConfiguredProof"
        let bytes = TLAValue.tuple(cfg.utf8.map { .int(Int($0)) })
        let pages = (1...((cfg.utf8.count + 15) / 16)).map { "CallerInputPage\($0)" }.joined(separator: " ")
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
        let nativeConclusion = nativeProof == nil ? "" : #"""
        /\ (AuthoredSequentialTypedEntry =>
                \A label : NativeSequentialLabeledStep(label) <=> TLASequentialLabeledStep(label))
        """#
        let nativeFact = nativeProof == nil ? "" : ", NativeSequentialDispatchUsesEmittedLabeledSteps"
        let configured = #"""
        ---- MODULE \#(configuredModule) ----
        EXTENDS \#(controlModule), CallerInputPageBlock1

        \* \#(pages)
        SequentialActualCFG == [i \in 1..CallerInputSize |-> CallerInputByte[i - 1]]
        SequentialNormalCFG == \#(bytes)
        \#(initialDefinition)
        \#(nativeProof?.definitions ?? "")
        \#(nativeProof?.theorem ?? "")

        THEOREM NormalConfigurationUsesOnlyAuthoredSequentialControl ==
            /\ SequentialActualCFG = SequentialNormalCFG
            /\ (Spec => AuthoredSequentialInitialControl)
            \#(initialConclusion)
            /\ (Spec => [][AuthoredSequentialStep]_vars)
            \#(typedConclusions)
            \#(nativeConclusion)
            /\ (~AuthoredSequentialGuard => ~ENABLED Next)
            /\ (AuthoredSequentialWriteFreeGuard => ENABLED Next)
            /\ PhysicalAuthoredSequentialTrace = LoweredSequentialSemantics
            /\ DeclaredSequentialConstructorsMatch(LoweredSequentialSemantics)
        PROOF
        <1>domain. DOMAIN SequentialActualCFG = DOMAIN SequentialNormalCFG
            BY ONLY SMT DEF SequentialActualCFG, SequentialNormalCFG, CallerInputSize
        <1>bytes. \A i \in DOMAIN SequentialNormalCFG : SequentialActualCFG[i] = SequentialNormalCFG[i]
            BY ONLY CallerInputPageBlock1AtFileOffsets, SMT DEF SequentialActualCFG, SequentialNormalCFG, CallerInputSize
        <1>configuration. SequentialActualCFG = SequentialNormalCFG
            BY ONLY <1>domain, <1>bytes, SMT DEF SequentialActualCFG, SequentialNormalCFG
        \#(initialStep)
        \#(typedSteps)
        <1>. QED BY ONLY <1>configuration, ActualSpecUsesOnlyAuthoredSequentialControl,
            ActualLoweredRoutesUseTheDeclaredSequentialConstructors\#(initialFact)\#(typedFacts)\#(nativeFact)

        ====

        """#
        return .init(controlModule: controlModule, control: Data(control.utf8),
                     configuredModule: configuredModule, configured: Data(configured.utf8))
    }
}
