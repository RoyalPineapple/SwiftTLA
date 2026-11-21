import SwiftParser
import SwiftSyntax
import SwiftTLA

// Read the same scoped Algorithm for copy binding and sequential-control evidence.
enum AuthoredCopySyntax {
    struct Selection {
        fileprivate let members: MemberBlockItemListSyntax
        fileprivate let algorithm: String
        fileprivate let scope: String
        fileprivate let body: CodeBlockItemListSyntax
    }

    private struct Label: Hashable {
        let enumName: String
        let caseName: String
    }

    private static func specification(source: String, modelName: String) throws
        -> (MemberBlockItemListSyntax, ClosureExprSyntax) {
        let file = Parser.parse(source: source)
        let models = file.statements.compactMap { $0.item.as(StructDeclSyntax.self) }
            .filter { name($0.name) == modelName }
        guard !file.hasError, models.count == 1, let model = models.first else { throw unsupported }
        let members = model.memberBlock.members
        let specs = members.compactMap { $0.decl.as(VariableDeclSyntax.self) }.filter { declaration in
            declaration.bindings.contains { $0.pattern.as(IdentifierPatternSyntax.self)?.identifier.text == "spec" }
        }
        guard specs.count == 1, let spec = specs.first,
              spec.modifiers.contains(where: { $0.name.text == "static" }),
              spec.bindings.count == 1, let binding = spec.bindings.first, binding.initializer == nil,
              let body = binding.accessorBlock?.accessors.as(CodeBlockItemListSyntax.self), body.count == 1,
              let macro = body.first?.item.as(MacroExpansionExprSyntax.self), macro.macroName.text == "spec",
              let specBody = macro.trailingClosure else { throw unsupported }

        return (members, specBody)
    }

    static func select(source: String, modelName: String) throws -> Selection {
        let (members, specBody) = try specification(source: source, modelName: modelName)
        let registered = specBody.statements.compactMap { reference($0.item.as(ExprSyntax.self)) }
        let algorithms = specBody.statements.compactMap { item -> (binding: String, call: FunctionCallExprSyntax)? in
            guard let (binding, value) = letBinding(item), registered.filter({ $0 == binding }).count == 1,
                  let call = value.as(FunctionCallExprSyntax.self), reference(call.calledExpression) == "Algorithm" else { return nil }
            return (binding, call)
        }
        guard algorithms.count == 1, let (binding, algorithm) = algorithms.first,
              algorithm.trailingClosure == nil, algorithm.additionalTrailingClosures.isEmpty,
              algorithm.arguments.filter({ $0.label?.text == "scoped" }).count == 1,
              algorithm.arguments.allSatisfy({ ["label", "scoped"].contains($0.label?.text ?? "") }),
              let algorithmBody = algorithm.arguments.first(where: { $0.label?.text == "scoped" })?
                .expression.as(ClosureExprSyntax.self),
              let scope = algorithmBody.signature?.parameterClause?.as(ClosureShorthandParameterListSyntax.self),
              scope.count == 1, let parameter = scope.first else { throw unsupported }
        return Selection(members: members, algorithm: binding, scope: name(parameter.name),
                         body: algorithmBody.statements)
    }

    static func proofInputs(_ selection: Selection) throws -> String {
        var declarations: [String] = []
        var localBindings: Set<String> = []
        var steps: [String] = []
        var enumNames: Set<String> = []
        for item in selection.body {
            if steps.isEmpty, let (binding, explicit) = try rootDeclaration(item, in: selection.scope) {
                guard localBindings.insert(binding).inserted else { throw unsupported }
                declarations.append("[binding |-> \(TLAValue.string(binding)), explicit |-> \(optionalLiteral(explicit))]")
                continue
            }
            guard let call = item.item.as(FunctionCallExprSyntax.self), reference(call.calledExpression) == "Do",
                  call.arguments.count == 1, let argument = call.arguments.first, argument.label == nil,
                  let label = labelReference(argument.expression),
                  call.additionalTrailingClosures.isEmpty,
                  let body = call.trailingClosure, !body.statements.isEmpty else { throw unsupported }
            let copies = try body.statements.map { statement -> String in
                guard let assign = statement.item.as(FunctionCallExprSyntax.self), reference(assign.calledExpression) == "Assign",
                      assign.trailingClosure == nil, assign.additionalTrailingClosures.isEmpty,
                      assign.arguments.count == 2, let target = assign.arguments.first, target.label == nil,
                      let read = assign.arguments.last, read.label?.text == "to",
                      let targetName = reference(target.expression), let readName = reference(read.expression) else { throw unsupported }
                return "[targetBinding |-> \(TLAValue.string(targetName)), readBinding |-> \(TLAValue.string(readName))]"
            }
            enumNames.insert(label.enumName)
            steps.append("[enumName |-> \(TLAValue.string(label.enumName)), caseName |-> \(TLAValue.string(label.caseName)), copies |-> \(tuple(copies))]")
        }
        guard !declarations.isEmpty, !steps.isEmpty else { throw unsupported }
        let enumCases = try enumBindings(in: selection.members, named: enumNames).map { label, explicit in
            "[enumName |-> \(TLAValue.string(label.enumName)), caseName |-> \(TLAValue.string(label.caseName)), explicit |-> \(optionalLiteral(explicit))]"
        }
        return #"""
        AuthoredCopyDeclarations == \#(set(declarations))
        AuthoredCopyEnumCases == \#(set(enumCases))
        AuthoredCopySteps == \#(tuple(steps))

        LOCAL NameOrSpelling(explicit, spelling) == IF explicit.present THEN explicit.value ELSE spelling
        LOCAL VariableNames(rows) == {NameOrSpelling(row.explicit, row.binding) : row \in rows}
        LOCAL BindingNames(binding) == VariableNames({row \in AuthoredCopyDeclarations : row.binding = binding})
        LOCAL LabelNames(step) ==
            {NameOrSpelling(row.explicit, row.caseName) : row \in
                {entry \in AuthoredCopyEnumCases : entry.enumName = step.enumName /\ entry.caseName = step.caseName}}
        LOCAL Single(values) == CHOOSE value \in values : TRUE

        AuthoredCopyFields == VariableNames(AuthoredCopyDeclarations)
        AuthoredCopyOrigins ==
            [binding \in {row.binding : row \in AuthoredCopyDeclarations} |-> Single(BindingNames(binding))]
        LOCAL CopyTargets(copies) == {copies[index].target : index \in DOMAIN copies}
        LOCAL ResolveCopy(copy) ==
            [target |-> Single(BindingNames(copy.targetBinding)), read |-> Single(BindingNames(copy.readBinding))]
        LOCAL ResolveCopies(step) == [index \in DOMAIN step.copies |-> ResolveCopy(step.copies[index])]
        LOCAL ResolveStep(step) ==
            [label |-> Single(LabelNames(step)), copies |-> ResolveCopies(step),
             frame |-> AuthoredCopyFields \ CopyTargets(ResolveCopies(step))]
        AuthoredCopyActionRows == [index \in DOMAIN AuthoredCopySteps |-> ResolveStep(AuthoredCopySteps[index])]

        THEOREM AuthoredCopySyntaxSuppliesTypedSchedulerInput ==
            /\ AuthoredCopyOrigins \in [DOMAIN AuthoredCopyOrigins -> AuthoredCopyFields]
            /\ \A row \in DOMAIN AuthoredCopySteps :
                LET raw == AuthoredCopySteps[row].copies
                    copies == AuthoredCopyActionRows[row].copies
                IN /\ Len(raw) \in Nat \ {0}
                   /\ DOMAIN raw = 1..Len(raw)
                   /\ copies = [position \in DOMAIN raw |-> copies[position]]
                   /\ \A position \in DOMAIN raw :
                          /\ raw[position].targetBinding \in DOMAIN AuthoredCopyOrigins
                          /\ raw[position].readBinding \in DOMAIN AuthoredCopyOrigins
                          /\ copies[position] =
                              [target |-> AuthoredCopyOrigins[raw[position].targetBinding],
                               read |-> AuthoredCopyOrigins[raw[position].readBinding]]
        PROOF
        <1>declarations. \A left, right \in AuthoredCopyDeclarations :
            left.binding = right.binding => left = right
            BY ONLY SMT DEF AuthoredCopyDeclarations
        <1>roots. \A binding \in DOMAIN AuthoredCopyOrigins :
            \E root \in AuthoredCopyFields : BindingNames(binding) = {root}
            BY ONLY <1>declarations, SetExtensionality, SMT
                DEF AuthoredCopyOrigins, BindingNames, AuthoredCopyFields, VariableNames
        <1>bindings. \A binding \in DOMAIN AuthoredCopyOrigins :
            AuthoredCopyOrigins[binding] \in AuthoredCopyFields
            BY ONLY <1>roots, SMT DEF AuthoredCopyOrigins, Single
        <1>typed. AuthoredCopyOrigins \in [DOMAIN AuthoredCopyOrigins -> AuthoredCopyFields]
            BY ONLY <1>bindings, SMT DEF AuthoredCopyOrigins
        <1>raw. \A row \in DOMAIN AuthoredCopySteps :
            LET raw == AuthoredCopySteps[row].copies
            IN /\ Len(raw) \in Nat \ {0}
               /\ DOMAIN raw = 1..Len(raw)
               /\ \A position \in DOMAIN raw :
                      /\ raw[position].targetBinding \in DOMAIN AuthoredCopyOrigins
                      /\ raw[position].readBinding \in DOMAIN AuthoredCopyOrigins
            BY ONLY SMT DEF AuthoredCopySteps, AuthoredCopyOrigins, AuthoredCopyDeclarations
        <1>rows. \A row \in DOMAIN AuthoredCopySteps :
            LET raw == AuthoredCopySteps[row].copies
                copies == AuthoredCopyActionRows[row].copies
            IN /\ copies = [position \in DOMAIN raw |-> copies[position]]
               /\ \A position \in DOMAIN raw :
                    (/\ raw[position].targetBinding \in DOMAIN AuthoredCopyOrigins
                     /\ raw[position].readBinding \in DOMAIN AuthoredCopyOrigins)
                    => copies[position] =
                          [target |-> AuthoredCopyOrigins[raw[position].targetBinding],
                           read |-> AuthoredCopyOrigins[raw[position].readBinding]]
            BY ONLY SMT DEF AuthoredCopyActionRows, ResolveStep, ResolveCopies, ResolveCopy, AuthoredCopyOrigins
        <1>. QED BY ONLY <1>typed, <1>raw, <1>rows, SMT

        LOCAL CopyNamesBind(raw, copy) ==
            /\ BindingNames(raw.targetBinding) = {copy.target}
            /\ BindingNames(raw.readBinding) = {copy.read}
            /\ copy = [target |-> copy.target, read |-> copy.read]

        LOCAL RowBindings(raw, witness) ==
            /\ LabelNames(raw) = {witness.label}
            /\ DOMAIN raw.copies = DOMAIN witness.copies
            /\ \A index \in DOMAIN witness.copies : CopyNamesBind(raw.copies[index], witness.copies[index])
            /\ AuthoredCopyFields \ CopyTargets(witness.copies) = witness.frame

        LOCAL CopyFunction(copies) == [index \in DOMAIN copies |-> copies[index]]
        LOCAL FunctionShapedStep(witness) ==
            [label |-> witness.label, copies |-> CopyFunction(witness.copies), frame |-> witness.frame]

        THEOREM LexicalBindingsDetermineTheOrderedCopyStep ==
            ASSUME NEW raw, NEW witness, RowBindings(raw, witness)
            PROVE ResolveStep(raw) = FunctionShapedStep(witness)
        PROOF
        <1>. DEFINE copies == witness.copies
        <1>label. Single(LabelNames(raw)) = witness.label BY SMT DEF RowBindings, Single
        <1>domains. DOMAIN ResolveCopies(raw) = DOMAIN copies BY SMT DEF RowBindings, ResolveCopies, copies
        <1>bindings. \A index \in DOMAIN copies : ResolveCopies(raw)[index] = copies[index]
            <2>. SUFFICES ASSUME NEW index \in DOMAIN copies
                         PROVE ResolveCopies(raw)[index] = copies[index]
                OBVIOUS
            <2>copy. CopyNamesBind(raw.copies[index], copies[index]) BY SMT DEF RowBindings, copies
            <2>names. /\ Single(BindingNames(raw.copies[index].targetBinding)) = copies[index].target
                      /\ Single(BindingNames(raw.copies[index].readBinding)) = copies[index].read
                BY ONLY <2>copy, SMT DEF CopyNamesBind, Single
            <2>. QED BY <2>copy, <2>names, SMT DEF RowBindings, CopyNamesBind, ResolveCopies, ResolveCopy, copies
        <1>rows. ResolveCopies(raw) = CopyFunction(copies)
            BY ONLY <1>domains, <1>bindings, SMT DEF ResolveCopies, CopyFunction
        <1>targets. CopyTargets(CopyFunction(copies)) = CopyTargets(copies)
            BY ONLY SMT DEF CopyFunction, CopyTargets
        <1>. QED BY <1>label, <1>rows, <1>targets, SMT DEF ResolveStep, FunctionShapedStep, RowBindings, copies

        THEOREM AuthoredCopySyntaxBindsWitnessRows ==
            /\ AuthoredCopyFields = WitnessCopyFields
            /\ AuthoredCopyActionRows = WitnessCopyActionRows
            /\ \A left, right \in DOMAIN AuthoredCopyActionRows :
                 left # right => AuthoredCopyActionRows[left].label # AuthoredCopyActionRows[right].label
        PROOF
        <1>fields. AuthoredCopyFields = WitnessCopyFields
            BY ONLY SMT DEF AuthoredCopyFields, AuthoredCopyDeclarations, VariableNames, NameOrSpelling, WitnessCopyFields
        <1>domain. DOMAIN AuthoredCopyActionRows = DOMAIN WitnessCopyActionRows
            BY ONLY SMT DEF AuthoredCopyActionRows, AuthoredCopySteps, WitnessCopyActionRows
        <1>points. \A row \in DOMAIN WitnessCopyActionRows :
            AuthoredCopyActionRows[row] = WitnessCopyActionRows[row]
            PROOF
            <2>. SUFFICES ASSUME NEW row \in DOMAIN WitnessCopyActionRows
                         PROVE AuthoredCopyActionRows[row] = WitnessCopyActionRows[row]
                OBVIOUS
            <2>. DEFINE raw == AuthoredCopySteps[row]
                        witness == WitnessCopyActionRows[row]
            <2>label. LabelNames(raw) = {witness.label}
                BY ONLY (row \in DOMAIN WitnessCopyActionRows), SMT
                    DEF raw, witness, AuthoredCopySteps, WitnessCopyActionRows,
                        LabelNames, NameOrSpelling, AuthoredCopyEnumCases
            <2>count. DOMAIN raw.copies = DOMAIN witness.copies
                BY ONLY (row \in DOMAIN WitnessCopyActionRows), SMT
                    DEF raw, witness, AuthoredCopySteps, WitnessCopyActionRows
            <2>all. \A index \in DOMAIN witness.copies : CopyNamesBind(raw.copies[index], witness.copies[index])
                PROOF
                <3>. SUFFICES ASSUME NEW index \in DOMAIN witness.copies
                             PROVE CopyNamesBind(raw.copies[index], witness.copies[index])
                    OBVIOUS
                <3>target. BindingNames(raw.copies[index].targetBinding) = {witness.copies[index].target}
                    BY ONLY (row \in DOMAIN WitnessCopyActionRows), (index \in DOMAIN witness.copies), SMT
                        DEF raw, witness, AuthoredCopySteps, WitnessCopyActionRows, BindingNames,
                            VariableNames, NameOrSpelling, AuthoredCopyDeclarations
                <3>read. BindingNames(raw.copies[index].readBinding) = {witness.copies[index].read}
                    BY ONLY (row \in DOMAIN WitnessCopyActionRows), (index \in DOMAIN witness.copies), SMT
                        DEF raw, witness, AuthoredCopySteps, WitnessCopyActionRows, BindingNames,
                            VariableNames, NameOrSpelling, AuthoredCopyDeclarations
                <3>shape. witness.copies[index] =
                    [target |-> witness.copies[index].target, read |-> witness.copies[index].read]
                    BY ONLY (row \in DOMAIN WitnessCopyActionRows), (index \in DOMAIN witness.copies), SMT
                        DEF witness, WitnessCopyActionRows
                <3>. QED BY ONLY <3>target, <3>read, <3>shape DEF CopyNamesBind
            <2>frame. AuthoredCopyFields \ CopyTargets(witness.copies) = witness.frame
                BY ONLY (row \in DOMAIN WitnessCopyActionRows), <1>fields, SMT
                    DEF witness, WitnessCopyActionRows, WitnessCopyFields, CopyTargets
            <2>bindings. RowBindings(raw, witness)
                BY ONLY <2>label, <2>count, <2>all, <2>frame DEF RowBindings
            <2>resolved. ResolveStep(raw) = FunctionShapedStep(witness)
                BY ONLY <2>bindings, LexicalBindingsDetermineTheOrderedCopyStep, SMT
            <2>shape. FunctionShapedStep(witness) = witness
                BY ONLY (row \in DOMAIN WitnessCopyActionRows), SMT
                    DEF FunctionShapedStep, CopyFunction, witness, WitnessCopyActionRows
            <2>. QED BY ONLY (row \in DOMAIN WitnessCopyActionRows), <1>domain, <2>resolved, <2>shape, SMT
                DEF AuthoredCopyActionRows, AuthoredCopySteps, raw, witness, WitnessCopyActionRows
        <1>functions. AuthoredCopyActionRows = CopyFunction(WitnessCopyActionRows)
            BY ONLY <1>domain, <1>points, SMT DEF AuthoredCopyActionRows, CopyFunction
        <1>rows. AuthoredCopyActionRows = WitnessCopyActionRows
            BY ONLY <1>functions, SMT DEF CopyFunction, WitnessCopyActionRows
        <1>labels. \A left, right \in DOMAIN WitnessCopyActionRows :
                     left # right => WitnessCopyActionRows[left].label # WitnessCopyActionRows[right].label
            BY ONLY SMT DEF WitnessCopyActionRows
        <1>. QED BY ONLY <1>fields, <1>rows, <1>labels, SMT
        """#
    }

    struct UnsupportedControlSyntax: Error {
        let reason: String
    }

    static func controlMachine(_ selection: Selection) throws -> SequentialControlEvidence.Machine {
        let body = try authoredSteps(selection)
        guard let machine = SequentialControlEvidence.authoredMachine(steps: body.steps, algorithmName: selection.algorithm)
        else { throw unsupported }
        return machine
    }

    private static func authoredSteps(_ selection: Selection) throws -> (fields: Set<String>, steps: [AlgorithmStepModel]) {
        var roots: [String: String] = [:]
        var steps: [AlgorithmStepModel] = []
        var labels: [Label: String] = [:]
        var enumNames: Set<String> = []

        func resolve(_ expression: ExprSyntax?) throws -> String {
            guard let key = labelReference(expression) else {
                throw UnsupportedControlSyntax(reason: "The proof requires a model-local String enum case reference for each label.")
            }
            if enumNames.insert(key.enumName).inserted {
                for (item, raw) in try enumBindings(in: selection.members, named: [key.enumName]) {
                    labels[item] = raw ?? item.caseName
                }
            }
            guard let label = labels[key] else {
                throw UnsupportedControlSyntax(reason: "The control label \(key.enumName).\(key.caseName) has no declared case.")
            }
            return label
        }

        for item in selection.body {
            if steps.isEmpty, let (binding, explicit) = try rootDeclaration(item, in: selection.scope) {
                guard roots.updateValue(explicit ?? binding, forKey: binding) == nil else { throw unsupported }
                continue
            }
            guard let call = item.item.as(FunctionCallExprSyntax.self),
                  let kind = reference(call.calledExpression), ["Do", "While"].contains(kind),
                  let label = call.arguments.first, label.label == nil,
                  let body = call.trailingClosure, body.signature == nil, call.additionalTrailingClosures.isEmpty else {
                throw UnsupportedControlSyntax(reason: "Expected a shared declaration followed by sequential Do or While blocks.")
            }
            let extra = call.arguments.dropFirst()
            let loop: StateExpr?
            var statements = try controlStatements(body.statements, roots: roots, resolve: resolve)
            if kind == "While", extra.count == 1, let predicate = extra.first, predicate.label == nil {
                loop = try controlExpression(predicate.expression, roots: roots)
            } else if kind == "Do", extra.count <= 1, extra.allSatisfy({ $0.label?.text == "when" }) {
                loop = nil
                if let predicate = extra.first {
                    statements.insert(.when(try controlExpression(predicate.expression, roots: roots)), at: 0)
                }
            } else {
                throw UnsupportedControlSyntax(reason: "Expected a While condition or one optional Do when: condition.")
            }
            steps.append(.init(label: .init(name: try resolve(label.expression)), statements: statements, loopCondition: loop))
        }
        let fields = Set(roots.values)
        guard fields.count == roots.count, !steps.isEmpty, Set(steps.map(\.label)).count == steps.count else {
            throw UnsupportedControlSyntax(reason: "Expected distinct roots and a nonempty sequence of distinct control labels.")
        }
        return (fields, steps)
    }

    static func arithmeticProofInput(_ selection: Selection, spec: TLASpec) throws -> (label: String, module: String) {
        let authored = try authoredSteps(selection)
        guard authored.steps.count == 1, let step = authored.steps.first, step.loopCondition == nil,
              let fallback = authored.fields.sorted().first,
              spec.sourceAlgorithms.count == 1, let built = spec.sourceAlgorithms.first?.model,
              built.name == selection.algorithm else { throw unsupported }
        let actual = built.components.compactMap { component -> AlgorithmStepModel? in
            guard case .step(let result) = component else { return nil }
            return result
        }
        let fields = built.components.compactMap { component -> String? in
            guard case .shared(let declaration) = component else { return nil }
            return declaration.root
        }
        guard fields.count == authored.fields.count, Set(fields) == authored.fields,
              actual.count == 1, let action = actual.first, action.label == step.label, action.loopCondition == nil,
              action.statements.count == step.statements.count else { throw unsupported }
        let rows = try zip(step.statements, action.statements).map { source, returned in
            guard case .set(.root(let target), let sourceValue) = source, authored.fields.contains(target),
                  case .set(.root(let actualTarget), let expression) = returned,
                  actualTarget == target, expression == sourceValue,
                  let certificate = StraightLineAssignmentCheck.orderedIntCertificate(expression, reads: authored.fields)
            else { throw unsupported }
            let syntax = try InitialFailureEvidence.sourceSyntaxView(certificate)
            let retained = "[view |-> \(syntax.view), origins |-> \(syntax.origins), inverse |-> \(syntax.indices)]"
            return (target: TLAValue.string(target).description, retained: retained, nodes: syntax.emitted)
        }
        let countColumns = tuple(rows.map { String($0.nodes.count) })
        let kindColumns = tuple(rows.map { tuple($0.nodes.map { TLAValue.string($0.kind).description }) })
        let literalColumns = tuple(rows.map { tuple($0.nodes.map { $0.kind == "literal" ? $0.payload : "0" }) })
        let formalFallback = TLAValue.string(fallback).description
        let readColumns = tuple(rows.map { tuple($0.nodes.map { $0.kind == "read" ? $0.payload : formalFallback }) })
        let leftColumns = tuple(rows.map { tuple($0.nodes.map { String($0.left) }) })
        let rightColumns = tuple(rows.map { tuple($0.nodes.map { String($0.right) }) })
        guard case .set(.root(let firstTarget), _)? = step.statements.first else { throw unsupported }
        return (step.label.name, #"""
        ---- MODULE SwiftTLAArithmeticAssignmentSource ----
        EXTENDS TLAPS, Integers, Sequences
        MasterFields == \#(TLAValue.set(Set(authored.fields.map(TLAValue.string))))
        MasterTarget == \#(TLAValue.string(firstTarget))
        MasterTargets == \#(tuple(rows.map(\.target)))
        MasterNodeCounts == \#(countColumns)
        MasterNodeKinds == \#(kindColumns)
        MasterNodeLiterals == \#(literalColumns)
        MasterNodeReadKeys == \#(readColumns)
        MasterNodeLeft == \#(leftColumns)
        MasterNodeRight == \#(rightColumns)
        LOCAL MasterRetainedRows == \#(tuple(rows.map(\.retained)))
        MasterRows == [index \in DOMAIN MasterNodeCounts |->
            LET row == MasterRetainedRows[index]
                count == MasterNodeCounts[index]
                nodes == [node \in 1..count |->
                    [kind |-> MasterNodeKinds[index][node],
                     payload |-> IF MasterNodeKinds[index][node] = "read"
                                 THEN MasterNodeReadKeys[index][node] ELSE MasterNodeLiterals[index][node],
                     left |-> MasterNodeLeft[index][node], right |-> MasterNodeRight[index][node]]]
            IN [target |-> MasterTargets[index], view |-> row.view, inverse |-> row.inverse, fallback |-> \#(formalFallback),
                emitted |-> [count |-> count, height |-> 1, indices |-> <<count>>, origins |-> row.origins, nodes |-> nodes]]]

        Rule == INSTANCE OrderedAssignmentOutputRules WITH Keys <- MasterFields,
            SwiftIntMin <- \#(TLAValue.int(Int.min)), SwiftIntMax <- \#(TLAValue.int(Int.max)),
            Vars <- {}, Values <- {}, ActionLabels <- {}, FailureValues <- {}, NoFailure <- <<>>
        THEOREM MasterAssignmentsAreSupported ==
            /\ Rule!SupportedAssignmentList(MasterRows)
            /\ Len(MasterRows) = \#(rows.count)
        PROOF
        <1>shape. /\ Len(MasterRows) \in Nat
                  /\ DOMAIN MasterRows = 1..Len(MasterRows)
                  /\ Len(MasterRows) = \#(rows.count)
            <2>domain. DOMAIN MasterRows = 1..\#(rows.count)
                BY ONLY SMT DEF MasterRows, MasterNodeCounts
            <2>. DEFINE values == {MasterRows[index] : index \in DOMAIN MasterRows}
            <2>function. MasterRows \in [1..\#(rows.count) -> values]
                BY ONLY <2>domain, SMT DEF values, MasterRows
            <2>sequence. MasterRows \in Seq(values)
                BY ONLY <2>function, Rule!SeqDef, SMT
            <2>. QED BY ONLY <2>domain, <2>sequence, Rule!LenProperties, SMT
        <1>rows. \A i \in DOMAIN MasterRows :
            /\ MasterRows[i].target \in MasterFields
            /\ Rule!AssignmentRhsCertificate(MasterRows[i])
            <2>. SUFFICES ASSUME NEW i \in DOMAIN MasterRows
                         PROVE /\ MasterRows[i].target \in MasterFields
                               /\ Rule!AssignmentRhsCertificate(MasterRows[i])
                OBVIOUS
            <2>. DEFINE row == MasterRows[i]
            <2>types. /\ row.target \in MasterFields /\ row.fallback \in MasterFields
                      /\ Rule!NodeEmissionArrays(row.emitted) /\ row.emitted.count > 0
                BY ONLY (i \in DOMAIN MasterRows), SMT DEF row, MasterRows, MasterNodeCounts, MasterRetainedRows, MasterTargets, MasterFields, Rule!NodeEmissionArrays
            <2>domains. /\ row.inverse \in [DOMAIN row.view.kinds -> 1..row.emitted.count]
                         /\ row.emitted.origins \in [1..row.emitted.count -> DOMAIN row.view.kinds]
                BY ONLY (i \in DOMAIN MasterRows), SMT DEF row, MasterRows, MasterNodeCounts, MasterRetainedRows
            <2>preorder. \A j \in 1..row.emitted.count : row.inverse[row.emitted.origins[j]] = j
                BY ONLY (i \in DOMAIN MasterRows), SMT DEF row, MasterRows, MasterNodeCounts, MasterRetainedRows
            <2>postorder. \A node \in DOMAIN row.view.kinds : row.emitted.origins[row.inverse[node]] = node
                BY ONLY (i \in DOMAIN MasterRows), SMT DEF row, MasterRows, MasterNodeCounts, MasterRetainedRows
            <2>root. row.emitted.origins[row.emitted.count] = row.view.root
                BY ONLY (i \in DOMAIN MasterRows), SMT DEF row, MasterRows, MasterNodeCounts, MasterRetainedRows
            <2>payload. Rule!AllNodePayloadsMatchSource(row.view, row.emitted)
                BY ONLY (i \in DOMAIN MasterRows), SMT DEF row, MasterRows, MasterNodeCounts, MasterRetainedRows, MasterNodeKinds, MasterNodeReadKeys,
                    MasterNodeLiterals, MasterNodeLeft, MasterNodeRight, Rule!AllNodePayloadsMatchSource, Rule!NodePayloadMatchesSource
            <2>bound. /\ Rule!TypedVisitedSourceInputs(row.view, row.emitted)
                      /\ \A j \in 1..row.emitted.count :
                             row.emitted.nodes[j].kind = "read" => row.emitted.nodes[j].payload \in MasterFields
                BY ONLY (i \in DOMAIN MasterRows), SMT DEF row, MasterRows, MasterNodeCounts, MasterRetainedRows, MasterNodeKinds, MasterNodeReadKeys,
                    MasterFields, Rule!TypedVisitedSourceInputs, Rule!InRange
            <2>. QED BY ONLY <2>types, <2>domains, <2>preorder, <2>postorder, <2>root, <2>payload, <2>bound, SMT
                DEF row, Rule!AssignmentRhsCertificate, Rule!LiteralReadAddCertificate
        <1>. QED BY ONLY <1>shape, <1>rows, SMT DEF Rule!SupportedAssignmentList
        ====
        """# + "\n")
    }

    static func conditionalProofInput(source: String, modelName: String) throws -> TLAValue? {
        let (members, specBody) = try specification(source: source, modelName: modelName)
        guard let parameters = specBody.signature?.parameterClause?.as(ClosureShorthandParameterListSyntax.self),
              parameters.count == 1, let parameter = parameters.first,
              let call = specBody.statements.last?.item.as(FunctionCallExprSyntax.self),
              reference(call.calledExpression) == "Do",
              call.arguments.count == 1, let argument = call.arguments.first, argument.label == nil,
              let label = labelReference(argument.expression),
              let body = call.trailingClosure, body.signature == nil, call.additionalTrailingClosures.isEmpty,
              let declaredLabel = try enumBindings(in: members, named: [label.enumName]).first(where: { $0.0 == label })
        else { return nil }

        var roots: [String: String] = [:]
        for item in specBody.statements.dropLast() {
            guard let (binding, explicit) = try rootDeclaration(item, in: name(parameter.name)),
                  roots.updateValue(explicit ?? binding, forKey: binding) == nil else { return nil }
        }
        let fields = Set(roots.values.map(TLAValue.string))
        guard fields.count == roots.count else { return nil }
        let statements = try controlStatements(body.statements, roots: roots, resolve: { _ in throw unsupported })
        guard statements.count == 1, case .ifElse(let predicate, let yes, let no)? = statements.first,
              let guardTerm = scalarComparison(predicate), let yesWrite = conditionalWrite(yes),
              let noWrite = conditionalWrite(no) else { return nil }

        return .record(["fields": .set(fields), "label": .string(declaredLabel.1 ?? label.caseName),
                        "predicate": guardTerm, "ifTrue": yesWrite, "ifFalse": noWrite])
    }

    private static func scalarComparison(_ expression: StateExpr) -> TLAValue? {
        func isOperand(_ value: StateExpr) -> Bool {
            switch value {
            case .variable, .value(.int), .value(.bool): true
            default: false
            }
        }
        switch expression {
        case .equal(let lhs, let rhs), .lessThan(let lhs, let rhs):
            guard isOperand(lhs), isOperand(rhs) else { return nil }
            return expression.scalarEvidenceTerm
        default: return nil
        }
    }

    private static func conditionalWrite(_ statements: [AlgorithmStatementModel]) -> TLAValue? {
        guard statements.count == 1,
              case .set(.root(let target), let value)? = statements.first,
              case .value(.bool) = value, let term = value.scalarEvidenceTerm else { return nil }
        return .tuple([.string(target), term])
    }

    private static func controlStatements(_ statements: CodeBlockItemListSyntax, roots: [String: String],
                                          resolve: (ExprSyntax?) throws -> String) throws -> [AlgorithmStatementModel] {
        try statements.map { item in
            let error = UnsupportedControlSyntax(reason: "Unsupported control statement: \(item.trimmedDescription)")
            guard let call = item.item.as(FunctionCallExprSyntax.self), let kind = reference(call.calledExpression) else {
                throw error
            }
            if kind == "If" {
                let extra = call.arguments.dropFirst()
                guard let predicate = call.arguments.first, predicate.label == nil,
                      let body = call.trailingClosure, body.signature == nil,
                      extra.count + call.additionalTrailingClosures.count <= 1,
                      extra.allSatisfy({ $0.label?.text == "else" }),
                      call.additionalTrailingClosures.allSatisfy({ $0.label.text == "else" }) else { throw error }
                let noClosure = call.additionalTrailingClosures.first?.closure ?? extra.first?.expression.as(ClosureExprSyntax.self)
                guard (extra.isEmpty || noClosure != nil), noClosure?.signature == nil else { throw error }
                let yes = try controlStatements(body.statements, roots: roots, resolve: resolve)
                let no = try noClosure.map { try controlStatements($0.statements, roots: roots, resolve: resolve) } ?? []
                return .ifElse(try controlExpression(predicate.expression, roots: roots), yes, no)
            }
            guard call.trailingClosure == nil, call.additionalTrailingClosures.isEmpty else { throw error }
            switch kind {
            case "Stop" where call.arguments.isEmpty: return .stop
            case "Skip" where call.arguments.isEmpty: return .skip
            case "When", "Goto":
                guard call.arguments.count == 1, let argument = call.arguments.first, argument.label == nil else { throw error }
                if kind == "When" { return .when(try controlExpression(argument.expression, roots: roots)) }
                return .goto(.init(name: try resolve(argument.expression)))
            case "Assign":
                guard call.arguments.count == 2, let target = call.arguments.first, target.label == nil,
                      let binding = reference(target.expression), let root = roots[binding],
                      let value = call.arguments.last, value.label?.text == "to" else { throw error }
                return .set(target: .root(root), value: try controlExpression(value.expression, roots: roots))
            default: throw error
            }
        }
    }

    // shortcut: The retained source evidence uses scalar reads, literals, and explicitly grouped built-in operations.
    private static func controlExpression(_ expression: ExprSyntax, roots: [String: String]) throws -> StateExpr {
        let error = UnsupportedControlSyntax(reason: "Unsupported scalar control expression: \(expression.trimmedDescription)")
        if let binding = reference(expression), let root = roots[binding] { return .variable(root) }
        if let member = expression.as(MemberAccessExprSyntax.self), name(member.declName.baseName) == "expr",
           let binding = reference(member.base), let root = roots[binding] { return .variable(root) }
        if let literal = expression.as(BooleanLiteralExprSyntax.self) { return .value(.bool(literal.literal.text == "true")) }
        let sign = expression.as(PrefixOperatorExprSyntax.self)
        if sign == nil || sign?.operator.text == "-" || sign?.operator.text == "+",
           let literal = (sign?.expression ?? expression).as(IntegerLiteralExprSyntax.self) {
            let spelling = literal.literal.text.filter { $0 != "_" }
            let radix: Int
            switch spelling.prefix(2) {
            case "0b": radix = 2
            case "0o": radix = 8
            case "0x": radix = 16
            default: radix = 10
            }
            let digits = radix == 10 ? spelling[...] : spelling.dropFirst(2)
            guard let value = Int((sign?.operator.text ?? "") + digits, radix: radix) else { throw error }
            return .value(.int(value))
        }
        if let group = expression.as(TupleExprSyntax.self), group.elements.count == 1,
           let part = group.elements.first, part.label == nil {
            return try controlExpression(part.expression, roots: roots)
        }
        if let prefix = expression.as(PrefixOperatorExprSyntax.self), prefix.operator.text == "!" {
            return .not(try controlExpression(prefix.expression, roots: roots))
        }
        let elements: [ExprSyntax]
        if let sequence = expression.as(SequenceExprSyntax.self) { elements = Array(sequence.elements) }
        else if let infix = expression.as(InfixOperatorExprSyntax.self) {
            elements = [infix.leftOperand, infix.operator, infix.rightOperand]
        } else { throw error }
        if elements.count > 3, !elements.count.isMultiple(of: 2),
           stride(from: 1, to: elements.count, by: 2).allSatisfy({
               elements[$0].as(BinaryOperatorExprSyntax.self)?.operator.text == "+"
           }) {
            var value = try controlExpression(elements[0], roots: roots)
            for index in stride(from: 2, to: elements.count, by: 2) {
                value = .add(value, try controlExpression(elements[index], roots: roots))
            }
            return value
        }
        guard elements.count == 3, let operation = elements[1].as(BinaryOperatorExprSyntax.self)?.operator.text else {
            throw error
        }
        let lhs = try controlExpression(elements[0], roots: roots)
        let rhs = try controlExpression(elements[2], roots: roots)
        switch operation {
        case "==": return .equal(lhs, rhs)
        case "!=": return .notEqual(lhs, rhs)
        case "<": return .lessThan(lhs, rhs)
        case "<=": return .lessOrEqual(lhs, rhs)
        case ">": return .greaterThan(lhs, rhs)
        case ">=": return .greaterOrEqual(lhs, rhs)
        case "&&": return .and(lhs, rhs)
        case "||": return .or(lhs, rhs)
        case "+": return .add(lhs, rhs)
        case "-": return .subtract(lhs, rhs)
        default: throw error
        }
    }

    private static var unsupported: InitialFailureEvidenceError { .unsupportedGeneratedOutput }

    private static func name(_ token: TokenSyntax) -> String { token.identifier?.name ?? token.text }

    private static func reference(_ expression: ExprSyntax?) -> String? {
        guard let token = expression?.as(DeclReferenceExprSyntax.self)?.baseName else { return nil }
        return name(token)
    }

    private static func letBinding(_ item: CodeBlockItemSyntax) -> (String, ExprSyntax)? {
        guard let declaration = item.item.as(VariableDeclSyntax.self), declaration.bindingSpecifier.text == "let",
              declaration.bindings.count == 1, let binding = declaration.bindings.first,
              let token = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier,
              let value = binding.initializer?.value, binding.accessorBlock == nil else { return nil }
        return (name(token), value)
    }

    private static func labelReference(_ expression: ExprSyntax?) -> Label? {
        guard let access = expression?.as(MemberAccessExprSyntax.self), let enumName = reference(access.base) else { return nil }
        return .init(enumName: enumName, caseName: name(access.declName.baseName))
    }

    private static func rootDeclaration(_ item: CodeBlockItemSyntax, in scope: String) throws -> (String, String?)? {
        guard let (binding, value) = letBinding(item), let call = value.as(FunctionCallExprSyntax.self),
              let member = call.calledExpression.as(MemberAccessExprSyntax.self),
              reference(member.base) == scope, name(member.declName.baseName) == "sharedVar",
              call.trailingClosure == nil, call.additionalTrailingClosures.isEmpty,
              call.arguments.filter({ $0.label?.text == "_name" }).count <= 1,
              call.arguments.allSatisfy({ ["_name", "label", "initial", "in"].contains($0.label?.text ?? "") }),
              call.arguments.filter({ $0.label?.text == "initial" || $0.label?.text == "in" }).count == 1 else { return nil }
        return (binding, try literal(call.arguments.first(where: { $0.label?.text == "_name" })?.expression))
    }

    private static func enumBindings(in members: MemberBlockItemListSyntax, named enumNames: Set<String>) throws
        -> [(Label, String?)] {
        let enums = members.compactMap { $0.decl.as(EnumDeclSyntax.self) }.filter { enumNames.contains(name($0.name)) }
        guard enums.count == enumNames.count, Set(enums.map { name($0.name) }) == enumNames else { throw unsupported }
        return try enums.flatMap { enumeration in
            guard enumeration.attributes.isEmpty, enumeration.genericParameterClause == nil,
                  let type = enumeration.inheritanceClause?.inheritedTypes.first?.type.as(IdentifierTypeSyntax.self),
                  name(type.name) == "String" else { throw unsupported }
            var caseNames: Set<String> = []
            return try enumeration.memberBlock.members.flatMap { member -> [(Label, String?)] in
                guard let cases = member.decl.as(EnumCaseDeclSyntax.self) else { throw unsupported }
                return try cases.elements.map { element in
                    guard element.parameterClause == nil, caseNames.insert(name(element.name)).inserted else { throw unsupported }
                    let explicit = try literal(element.rawValue?.value)
                    return (Label(enumName: name(enumeration.name), caseName: name(element.name)), explicit)
                }
            }
        }
    }

    private static func literal(_ expression: ExprSyntax?) throws -> String? {
        guard let expression else { return nil }
        guard let value = expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue else { throw unsupported }
        return value
    }

    private static func optionalLiteral(_ literal: String?) -> String {
        guard let literal else { return #"[present |-> FALSE, value |-> ""]"# }
        return "[present |-> TRUE, value |-> \(TLAValue.string(literal))]"
    }

    private static func set(_ rows: [String]) -> String { "{\(rows.joined(separator: ", "))}" }

    private static func tuple(_ rows: [String]) -> String { "<<\(rows.joined(separator: ", "))>>" }
}
