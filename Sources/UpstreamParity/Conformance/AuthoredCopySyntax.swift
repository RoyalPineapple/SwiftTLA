import SwiftParser
import SwiftSyntax
import SwiftTLA

// shortcut: Only model-local String enum labels and direct copies in a scoped Algorithm enter this proof.
enum AuthoredCopySyntax {
    static func proofInputs(source: String, modelName: String) throws -> String {
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

        let registered = specBody.statements.compactMap { reference($0.item.as(ExprSyntax.self)) }
        let algorithms = specBody.statements.compactMap { item -> FunctionCallExprSyntax? in
            guard let (binding, value) = letBinding(item), registered.filter({ $0 == binding }).count == 1,
                  let call = value.as(FunctionCallExprSyntax.self), reference(call.calledExpression) == "Algorithm" else { return nil }
            return call
        }
        guard algorithms.count == 1, let algorithm = algorithms.first,
              algorithm.trailingClosure == nil, algorithm.additionalTrailingClosures.isEmpty,
              algorithm.arguments.filter({ $0.label?.text == "scoped" }).count == 1,
              algorithm.arguments.allSatisfy({ ["label", "scoped"].contains($0.label?.text ?? "") }),
              let algorithmBody = algorithm.arguments.first(where: { $0.label?.text == "scoped" })?
                .expression.as(ClosureExprSyntax.self),
              let scope = algorithmBody.signature?.parameterClause?.as(ClosureShorthandParameterListSyntax.self),
              scope.count == 1, let parameter = scope.first else { throw unsupported }
        let scopeName = name(parameter.name)

        var declarations: [String] = []
        var localBindings: Set<String> = []
        var steps: [String] = []
        var copyCounts: [Int] = []
        var enumNames: Set<String> = []
        for item in algorithmBody.statements {
            if let (binding, value) = letBinding(item), steps.isEmpty,
               let call = value.as(FunctionCallExprSyntax.self),
               let member = call.calledExpression.as(MemberAccessExprSyntax.self),
               reference(member.base) == scopeName, name(member.declName.baseName) == "sharedVar",
               call.trailingClosure == nil, call.additionalTrailingClosures.isEmpty,
               call.arguments.filter({ $0.label?.text == "_name" }).count <= 1,
               call.arguments.allSatisfy({ ["_name", "label", "initial"].contains($0.label?.text ?? "") }),
               call.arguments.filter({ $0.label?.text == "initial" }).count == 1 {
                guard localBindings.insert(binding).inserted else { throw unsupported }
                let explicit = try optionalLiteral(call.arguments.first(where: { $0.label?.text == "_name" })?.expression)
                declarations.append("[binding |-> \(TLAValue.string(binding)), explicit |-> \(explicit)]")
                continue
            }
            guard let call = item.item.as(FunctionCallExprSyntax.self), reference(call.calledExpression) == "Do",
                  call.arguments.count == 1, let argument = call.arguments.first, argument.label == nil,
                  let label = argument.expression.as(MemberAccessExprSyntax.self), let enumName = reference(label.base),
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
            enumNames.insert(enumName)
            copyCounts.append(copies.count)
            steps.append("[enumName |-> \(TLAValue.string(enumName)), caseName |-> \(TLAValue.string(name(label.declName.baseName))), copies |-> \(tuple(copies))]")
        }
        guard !declarations.isEmpty, !steps.isEmpty else { throw unsupported }
        let enums = members.compactMap { $0.decl.as(EnumDeclSyntax.self) }.filter { enumNames.contains(name($0.name)) }
        guard enums.count == enumNames.count, Set(enums.map { name($0.name) }) == enumNames else { throw unsupported }
        let enumCases = try enums.flatMap { enumeration in
            guard enumeration.attributes.isEmpty, enumeration.genericParameterClause == nil,
                  let type = enumeration.inheritanceClause?.inheritedTypes.first?.type.as(IdentifierTypeSyntax.self),
                  name(type.name) == "String" else { throw unsupported }
            var caseNames: Set<String> = []
            return try enumeration.memberBlock.members.flatMap { member -> [String] in
                guard let cases = member.decl.as(EnumCaseDeclSyntax.self) else { throw unsupported }
                return try cases.elements.map { element in
                    guard element.parameterClause == nil, caseNames.insert(name(element.name)).inserted else { throw unsupported }
                    let explicit = try optionalLiteral(element.rawValue?.value)
                    return "[enumName |-> \(TLAValue.string(name(enumeration.name))), caseName |-> \(TLAValue.string(name(element.name))), explicit |-> \(explicit)]"
                }
            }
        }
        let rowProofs = copyCounts.enumerated().map { offset, count in
            let row = offset + 1
            let names = (1...count).map { index in
                #"""
                <2>copy\#(index). CopyNamesBind(raw.copies[\#(index)], witness.copies[\#(index)])
                    BY ONLY SMT DEF raw, witness, AuthoredCopySteps, WitnessCopyActionRows, CopyNamesBind,
                        BindingNames, VariableNames, NameOrSpelling, AuthoredCopyDeclarations
                """#
            }.joined(separator: "\n")
            let copyFacts = (1...count).map { "<2>copy\($0)" }.joined(separator: ", ")
            return #"""
            <1>row\#(row). AuthoredCopyActionRows[\#(row)] = WitnessCopyActionRows[\#(row)]
            PROOF
            <2>. DEFINE raw == AuthoredCopySteps[\#(row)]
                        witness == WitnessCopyActionRows[\#(row)]
            <2>label. LabelNames(raw) = {witness.label}
                BY ONLY SMT DEF raw, witness, AuthoredCopySteps, WitnessCopyActionRows,
                    LabelNames, NameOrSpelling, AuthoredCopyEnumCases
            <2>count. DOMAIN raw.copies = DOMAIN witness.copies
                BY ONLY SMT DEF raw, witness, AuthoredCopySteps, WitnessCopyActionRows
            \#(names)
            <2>all. \A index \in DOMAIN witness.copies : CopyNamesBind(raw.copies[index], witness.copies[index])
                BY ONLY \#(copyFacts), SMT DEF witness, WitnessCopyActionRows
            <2>frame. AuthoredCopyFields \ CopyTargets(witness.copies) = witness.frame
                BY ONLY <1>fields, SMT DEF witness, WitnessCopyActionRows, WitnessCopyFields, CopyTargets
            <2>bindings. RowBindings(raw, witness)
                BY ONLY <2>label, <2>count, <2>all, <2>frame, SMT DEF RowBindings
            <2>resolved. ResolveStep(raw) = FunctionShapedStep(witness)
                BY ONLY <2>bindings, LexicalBindingsDetermineTheOrderedCopyStep, SMT
            <2>shape. FunctionShapedStep(witness) = witness
                BY ONLY SMT DEF FunctionShapedStep, CopyFunction, witness, WitnessCopyActionRows
            <2>. QED BY ONLY <1>domain, <2>resolved, <2>shape, SMT
                DEF AuthoredCopyActionRows, AuthoredCopySteps, raw, witness, WitnessCopyActionRows
            """#
        }.joined(separator: "\n")
        let rowFacts = steps.indices.map { "<1>row\($0 + 1)" }.joined(separator: ", ")
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
        LOCAL CopyTargets(copies) == {copies[index].target : index \in DOMAIN copies}
        LOCAL ResolveCopy(copy) ==
            [target |-> Single(BindingNames(copy.targetBinding)), read |-> Single(BindingNames(copy.readBinding))]
        LOCAL ResolveCopies(step) == [index \in DOMAIN step.copies |-> ResolveCopy(step.copies[index])]
        LOCAL ResolveStep(step) ==
            [label |-> Single(LabelNames(step)), copies |-> ResolveCopies(step),
             frame |-> AuthoredCopyFields \ CopyTargets(ResolveCopies(step))]
        AuthoredCopyActionRows == [index \in DOMAIN AuthoredCopySteps |-> ResolveStep(AuthoredCopySteps[index])]

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
        \#(rowProofs)
        <1>points. \A index \in DOMAIN WitnessCopyActionRows : AuthoredCopyActionRows[index] = WitnessCopyActionRows[index]
            BY ONLY \#(rowFacts), SMT DEF WitnessCopyActionRows
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

    private static func optionalLiteral(_ expression: ExprSyntax?) throws -> String {
        guard let expression else { return #"[present |-> FALSE, value |-> ""]"# }
        guard let value = expression.as(StringLiteralExprSyntax.self)?.representedLiteralValue else { throw unsupported }
        return "[present |-> TRUE, value |-> \(TLAValue.string(value))]"
    }

    private static func set(_ rows: [String]) -> String { "{\(rows.joined(separator: ", "))}" }

    private static func tuple(_ rows: [String]) -> String { "<<\(rows.joined(separator: ", "))>>" }
}
