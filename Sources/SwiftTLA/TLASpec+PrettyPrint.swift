import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder

extension TLASpec {
    /// Renders the TLA+ module source for one specification.
    ///
    /// This is the compiler-internal renderer consumed by
    /// `CompiledSpecification.renderedTLAModuleBundle()`. Application code must
    /// compile first and read the bundle's `.tla` field instead of rendering a
    /// raw `TLASpec`.
    func renderTLAModuleSource() -> String {
        validateSymmetricCollectionExport()
        let varNames = variables.map(\.name)
        let algorithmSymbols = algorithmExportSymbols(sourceAlgorithms, actions: actions)
        let emittedActionNames = tlaActionNames(actions, preferredNames: algorithmSymbols.actionNames)
        let varsTuple = varNames.count == 1 ? varNames[0] : "<<\(varNames.joined(separator: ", "))>>"
        let isLibraryModule = variables.isEmpty && actions.isEmpty
        var lines: [String] = []

        let modName = name.replacingOccurrences(of: " ", with: "")
        lines.append("---- MODULE \(modName) ----")

        let symmetryModule = symmetrySets.isEmpty && symmetricCollections.isEmpty ? [] : ["TLC"]
        let importedNames = imports.map(\.name)
        let modules = (extendsModules.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespaces)
        } + ["FiniteSets", "Sequences"] + symmetryModule + importedNames)
            .reduce(into: [String]()) { names, module in
                if !names.contains(module) { names.append(module) }
            }
        lines.append("EXTENDS \(modules.joined(separator: ", "))")
        lines.append("")

        let generatedMemberSymbols = symmetricCollections.flatMap { collection in
            collection.metadata.generatedSymbols.filter { symbol in
                collection.metadata.members.contains(.constant(symbol))
            }
        }
        let formalConstantSymbols = formalParameters
            .filter { $0.kind == .constant }
            .map(\.name)
        let formalVariableSymbols = formalParameters
            .filter { $0.kind == .variable }
            .map(\.name)
        let allConstantSymbols = (constants.keys + formalConstantSymbols + generatedMemberSymbols).sorted()
        if !allConstantSymbols.isEmpty {
            lines.append("CONSTANTS \(allConstantSymbols.joined(separator: ", "))")
            for (name, value) in constants.sorted(by: { $0.key < $1.key }) {
                lines.append("ASSUME \(name) = \(value)")
            }
            lines.append("")
        }

        for collection in symmetricCollections {
            let metadata = collection.metadata
            lines.append("\(metadata.domainSymbol) == {\(metadata.members.map(\.description).joined(separator: ", "))}")
            lines.append("\(metadata.symmetrySymbol) == Permutations(\(metadata.domainSymbol))")
        }
        for sym in symmetrySets {
            let sortedVals = Array(sym.values).sorted(by: { $0.description < $1.description })
            let valList = sortedVals.map(\.description).joined(separator: ", ")
            lines.append("Symm\(sym.variableName) == Permutations({\(valList)})")
        }
        if !symmetricCollections.isEmpty || !symmetrySets.isEmpty { lines.append("") }

        if let assume = assume {
            lines.append("ASSUME \(assume.tlaModuleSource)")
            lines.append("")
        }

        if !isLibraryModule || !formalVariableSymbols.isEmpty {
            let symbols = (varNames + formalVariableSymbols).joined(separator: ", ")
            lines.append("VARIABLES \(symbols)")
            lines.append("")
        }

        for configuration in importConfigurations {
            for replacement in configuration.replacements {
                lines.append("\(replacement.definitionName) == \(replacement.expression)")
                lines.append("")
            }
        }

        let instanceDependentDefinitions = definitions.filter { definition in
            moduleInstances.contains { definition.contains("\($0.name)!") }
        }
        for def in definitions where !instanceDependentDefinitions.contains(def) {
            lines.append(def)
            lines.append("")
        }

        for rec in recursiveDefs {
            lines.append(rec)
            lines.append("")
        }

        for rf in recursiveFuncs {
            let underscores = rf.params.map { _ in "_" }.joined(separator: ", ")
            let params = rf.params.joined(separator: ", ")
            lines.append("RECURSIVE \(rf.name)(\(underscores))")
            lines.append("\(rf.name)(\(params)) == \(rf.body)")
            lines.append("")
        }

        for body in runtimeFuncBodies {
            lines.append(body)
            lines.append("")
        }

        // An INSTANCE's default substitutions resolve against declarations
        // already in scope.  Emit local definitions first so a same-named
        // refinement mapping, such as VoteProof's `chosen`, is available.
        for instance in moduleInstances {
            let arguments = instance.arguments.map { argument in
                "\(argument.parameter) <- \(argument.value)"
            }.joined(separator: ", ")
            let withClause = arguments.isEmpty ? "" : " WITH \(arguments)"
            lines.append("\(instance.name) == INSTANCE \(instance.module.name)\(withClause)")
            lines.append("")
        }

        for def in instanceDependentDefinitions {
            lines.append(def)
            lines.append("")
        }

        let varsDef = "vars == \(varsTuple)"
        if !isLibraryModule, varNames.count > 1 { lines.append(varsDef); lines.append("") }

        for inv in invariants {
            lines.append("\(inv.name) == \(inv.body.tlaModuleSource)")
        }
        if !invariants.isEmpty { lines.append("") }

        if let constraint = constraint {
            lines.append("StateConstraint == \(constraint.tlaModuleSource)")
            lines.append("")
        }

        guard !isLibraryModule else {
            lines.append("====")
            return lines.joined(separator: "\n") + "\n"
        }

        let symmetricMetadataByName = Dictionary(
            uniqueKeysWithValues: symmetricCollections.map { ($0.name, $0.metadata) }
        )
        let inits = variables.map { v -> String in
            if let metadata = symmetricMetadataByName[v.name] {
                return "\(v.name) = [member \\in \(metadata.domainSymbol) |-> \(metadata.initial)]"
            }
            if let s = v.lazySet { return "\(v.name) \\in \(s)" }
            if let s = v.initialSet { return "\(v.name) \\in \(s)" }
            if let expr = v.initExpr { return "\(v.name) = \(expr.tlaModuleSource)" }
            return "\(v.name) = \(v.initial)"
        }
        if inits.count == 1 {
            lines.append("Init == \(inits[0])")
        } else {
            lines.append("Init ==")
            for i in inits { lines.append("  /\\ \(i)") }
        }
        lines.append("")

        for action in actions where !action.name.isEmpty {
            let parameters = action.bindings.map(\.name).joined(separator: ", ")
            let emittedName = emittedActionNames[action.name] ?? action.name
            let header = parameters.isEmpty ? emittedName : "\(emittedName)(\(parameters))"
            lines.append("\(header) == \(action.body.tlaModuleSource)")
            for variant in actionInvocations(action) where !variant.indices.isEmpty {
                let suffix = variant.indices.map(String.init).joined(separator: "_")
                lines.append("\(emittedName)__\(suffix) == \(variant.invocation)")
            }
        }
        lines.append("")

        let actionNames = actions.filter { !$0.name.isEmpty }
        let invocations = actionNames.flatMap { action in
            actionInvocations(action).map { variant -> String in
                let emittedName = emittedActionNames[action.name] ?? action.name
                guard !variant.indices.isEmpty else { return emittedName }
                return "\(emittedName)__\(variant.indices.map(String.init).joined(separator: "_"))"
            }
        }
        if invocations.count == 1 && invocations[0] == "Next" {
            // Single action already named Next — no separate disjunction needed
        } else if invocations.count == 1 {
            lines.append("Next == \(invocations[0])")
        } else {
            lines.append("Next ==")
            for invocation in invocations {
                lines.append("  \\/ \(invocation)")
            }
        }
        lines.append("")

        lines.append("Spec ==")
        lines.append("  /\\ Init")
        lines.append("  /\\ [][Next]_\(varsTuple)")
        for f in fairness {
            lines.append("  /\\ \(fairnessForm(f, vars: varsTuple, emittedActionNames: emittedActionNames))")
        }
        lines.append("")

        for t in temporalProperties {
            lines.append("\(t.name) == \(t.expr.tlaModuleSource)")
        }
        if !temporalProperties.isEmpty { lines.append("") }

        for th in theorems {
            lines.append("THEOREM \(th)")
            lines.append("")
        }

        lines.append("====")
        return algorithmSymbols.rewrite(lines.joined(separator: "\n") + "\n")
    }

    private func fairnessForm(
        _ condition: FairnessCondition,
        vars: String,
        emittedActionNames: [String: String]
    ) -> String {
        switch condition {
        case .weakFairness, .strongFairness:
            return condition.tlaForm(vars: vars)
        case .weakFairnessInvocation(let invocation), .strongFairnessInvocation(let invocation):
            let operatorName = actions.lazy
                .flatMap(actionInvocations)
                .first(where: { $0.invocation == invocation })
                .map { variant in
                    let emittedName = emittedActionNames[invocation.name] ?? invocation.name
                    guard !variant.indices.isEmpty else { return emittedName }
                    return "\(emittedName)__\(variant.indices.map(String.init).joined(separator: "_"))"
                } ?? (emittedActionNames[invocation.name] ?? invocation.name)
            return condition.isStrong
                ? "SF_\(vars)(\(operatorName))"
                : "WF_\(vars)(\(operatorName))"
        }
    }

    /// Renders the auto-generated TLC configuration matching the module.
    ///
    /// Compiler-internal; application code must compile first and read the
    /// bundle's `.cfg` field.
    func renderTLCConfiguration() -> String {
        validateSymmetricCollectionExport()
        var lines: [String] = []
        lines.append("SPECIFICATION Spec")
        if checkDeadlock {
            lines.append("CHECK_DEADLOCK TRUE")
        } else {
            lines.append("CHECK_DEADLOCK FALSE")
        }
        for (name, value) in constants.sorted(by: { $0.key < $1.key }) {
            lines.append("CONSTANT \(name) = \(value)")
        }
        for configuration in importConfigurations {
            for replacement in configuration.replacements {
                lines.append(
                    "CONSTANT \(replacement.operatorName) <- [\(configuration.moduleName)]\(replacement.definitionName)"
                )
            }
        }
        for collection in symmetricCollections {
            for member in collection.metadata.members {
                lines.append("CONSTANT \(member) = \(member)")
            }
        }
        if constraint != nil { lines.append("CONSTRAINT StateConstraint") }
        for inv in invariants { lines.append("INVARIANT \(inv.name)") }
        for t in temporalProperties { lines.append("PROPERTY \(t.name)") }
        for sym in symmetrySets {
            lines.append("SYMMETRY Symm\(sym.variableName)")
        }
        for collection in symmetricCollections {
            lines.append("SYMMETRY \(collection.metadata.symmetrySymbol)")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private func validateSymmetricCollectionExport() {
        if let error = symmetricCollectionValidationError(permutationProductBudget: .max) {
            preconditionFailure("Cannot export symmetric collection specification: \(error)")
        }
    }
}

/// Runtime labels retain authored names. TLA+ operator identifiers cannot
/// contain every character the generated Swift surface may expose, so module
/// export owns a deterministic, collision-free symbol table.
private func tlaActionNames(
    _ actions: [NamedAction],
    preferredNames: [String: String] = [:]
) -> [String: String] {
    var emitted: [String: String] = [:]
    var used: Set<String> = []
    for action in actions where emitted[action.name] == nil {
        let raw = (preferredNames[action.name] ?? action.name).unicodeScalars.map { scalar -> String in
            switch scalar.value {
            case 48...57, 65...90, 97...122, 95: String(scalar)
            default: "_"
            }
        }.joined()
        let stem = raw.first?.isNumber == true ? "_\(raw)" : raw
        var candidate = stem.isEmpty ? "Action" : stem
        var suffix = 2
        while used.contains(candidate) {
            candidate = "\(stem)__\(suffix)"
            suffix += 1
        }
        emitted[action.name] = candidate
        used.insert(candidate)
    }
    return emitted
}

/// The generated Swift machine deliberately keeps qualified procedure action
/// names so application code never loses its source-level context.  PlusCal's
/// translator, however, emits the procedure label itself as the TLA+ operator
/// and stores that same label in `pc`.  Keep that distinction at the export
/// boundary: the executable Swift model remains stable while the independently
/// translated TLA+ modules expose the same administrative state.
private struct AlgorithmExportSymbols {
    let actionNames: [String: String]
    let stringLiterals: [String: String]

    func rewrite(_ source: String) -> String {
        var result = source
        // `__pcal_stack` is a SwiftTLA implementation identifier.  The
        // official translator calls the corresponding PlusCal variable
        // `stack`; its name is part of the TLC state graph.
        result = result.replacingOccurrences(of: "__pcal_stack", with: "stack")
        for (from, to) in stringLiterals {
            result = result.replacingOccurrences(of: "\"\(from)\"", with: "\"\(to)\"")
        }
        return result
    }
}

private func algorithmExportSymbols(
    _ algorithms: [Algorithm],
    actions: [NamedAction]
) -> AlgorithmExportSymbols {
    let actionNames = Set(actions.map(\.name))
    var candidates: [(qualified: String, label: String)] = []
    for algorithm in algorithms {
        for procedure in algorithm.model.procedures {
            for step in procedure.steps {
                candidates.append((
                    qualified: "procedure.\(procedure.name).\(step.label.name)",
                    label: step.label.name
                ))
            }
        }
    }

    // A PlusCal label is global.  Do not silently merge two SwiftTLA actions
    // if an unsupported source program reuses a label across scopes; the
    // normal renderer/translator path will then report the source problem.
    let labelCounts = Dictionary(grouping: candidates, by: { $0.label }).mapValues { $0.count }
    let unqualifiedActions = Set(actions.map(\.name)).subtracting(Set(candidates.map { $0.qualified }))
    let usable = candidates.filter {
        actionNames.contains($0.qualified)
            && labelCounts[$0.label] == 1
            && !unqualifiedActions.contains($0.label)
    }
    let names = Dictionary(uniqueKeysWithValues: usable.map { ($0.qualified, $0.label) })
    return AlgorithmExportSymbols(actionNames: names, stringLiterals: names)
}

/// Push UNCHANGED into every OR branch after distributing AND over OR.
/// Without distribution, `assignedVars` unions all branches and a variable
/// assigned in only one arm is treated as assigned in every arm (TLC error).
public func completeAction(_ e: ActionExpr, allVars: [String]) -> ActionExpr {
    let branches = distributeOr(e)
    let completed: [ActionExpr] = branches.map { branch in
        let assigned = assignedVars(branch)
        let explicit = explicitUnchanged(branch)
        var result = branch
        for v in allVars where !assigned.contains(v) && !explicit.contains(v) {
            result = .and(result, .unchanged(v))
        }
        return result
    }
    guard let first = completed.first else { return e }
    return completed.dropFirst().reduce(first) { .or($0, $1) }
}

public func distributeOr(_ action: ActionExpr) -> [ActionExpr] {
    switch action {
    case .or(let a, let b):
        return distributeOr(a) + distributeOr(b)
    case .and(let a, let b):
        let lhs = distributeOr(a)
        let rhs = distributeOr(b)
        return lhs.flatMap { l in rhs.map { r in .and(l, r) } }
    case .ifElse(let c, let t, let e):
        return distributeOr(.and(.guard_(c), t)) + distributeOr(.and(.guard_(StateExpr.not(c)), e))
    case .define(let variable, let value, let body):
        return distributeOr(body).map { .define(variable, value, $0) }
    case .existsAction(let v, let s, let b):
        return distributeOr(b).map { .existsAction(v, s, $0) }
    default:
        return [action]
    }
}
