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
        var steps: [String] = []
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
            steps.append("[enumName |-> \(TLAValue.string(enumName)), caseName |-> \(TLAValue.string(name(label.declName.baseName))), copies |-> \(tuple(copies))]")
        }
        guard !declarations.isEmpty, !steps.isEmpty else { throw unsupported }
        let enums = members.compactMap { $0.decl.as(EnumDeclSyntax.self) }.filter { enumNames.contains(name($0.name)) }
        guard enums.count == enumNames.count else { throw unsupported }
        let enumCases = try enums.flatMap { enumeration in
            guard enumeration.attributes.isEmpty, enumeration.genericParameterClause == nil,
                  let type = enumeration.inheritanceClause?.inheritedTypes.first?.type.as(IdentifierTypeSyntax.self),
                  name(type.name) == "String" else { throw unsupported }
            return try enumeration.memberBlock.members.flatMap { member -> [String] in
                guard let cases = member.decl.as(EnumCaseDeclSyntax.self) else { throw unsupported }
                return try cases.elements.map { element in
                    guard element.parameterClause == nil else { throw unsupported }
                    let explicit = try optionalLiteral(element.rawValue?.value)
                    return "[enumName |-> \(TLAValue.string(name(enumeration.name))), caseName |-> \(TLAValue.string(name(element.name))), explicit |-> \(explicit)]"
                }
            }
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
        LOCAL FirstStep == AuthoredCopySteps[1]
        LOCAL FirstCopy == FirstStep.copies[1]

        LOCAL Single(values) == CHOOSE value \in values : TRUE

        AuthoredCopyDescriptors(step, copy) ==
            LET labels == LabelNames(step)
                targets == BindingNames(copy.targetBinding)
                reads == BindingNames(copy.readBinding)
                label == Single(labels)
                target == Single(targets)
                read == Single(reads)
            IN IF /\ labels = {label} /\ targets = {target} /\ reads = {read}
               THEN {[label |-> label, target |-> target, read |-> read,
                      frame |-> VariableNames(AuthoredCopyDeclarations) \ {target}]}
               ELSE {}

        AuthoredCopyDescriptor == Single(AuthoredCopyDescriptors(FirstStep, FirstCopy))

        THEOREM AuthoredCopySyntaxBindsSourceIdentityAction ==
            /\ Len(AuthoredCopySteps) = 1
            /\ Len(AuthoredCopySteps[1].copies) = 1
            /\ AuthoredCopyDescriptors(AuthoredCopySteps[1], AuthoredCopySteps[1].copies[1]) = {SourceIdentityAction}
            /\ AuthoredCopyDescriptor = SourceIdentityAction
        PROOF
        <1>1. /\ Len(AuthoredCopySteps) = 1
              /\ Len(FirstStep.copies) = 1
            BY SMT DEF AuthoredCopySteps, FirstStep
        <1>2. LabelNames(FirstStep) = {SourceIdentityAction.label}
            BY ONLY SMT DEF LabelNames, NameOrSpelling, FirstStep, AuthoredCopySteps, AuthoredCopyEnumCases, SourceIdentityAction
        <1>3. BindingNames(FirstCopy.targetBinding) = {SourceIdentityAction.target}
            BY ONLY SMT DEF BindingNames, VariableNames, NameOrSpelling, FirstCopy, FirstStep,
                AuthoredCopySteps, AuthoredCopyDeclarations, SourceIdentityAction
        <1>4. BindingNames(FirstCopy.readBinding) = {SourceIdentityAction.read}
            BY ONLY SMT DEF BindingNames, VariableNames, NameOrSpelling, FirstCopy, FirstStep,
                AuthoredCopySteps, AuthoredCopyDeclarations, SourceIdentityAction
        <1>5. VariableNames(AuthoredCopyDeclarations) \ {SourceIdentityAction.target} = SourceIdentityAction.frame
            BY ONLY SMT DEF VariableNames, NameOrSpelling, AuthoredCopyDeclarations, SourceIdentityAction
        <1>6. /\ Single(LabelNames(FirstStep)) = SourceIdentityAction.label
              /\ Single(BindingNames(FirstCopy.targetBinding)) = SourceIdentityAction.target
              /\ Single(BindingNames(FirstCopy.readBinding)) = SourceIdentityAction.read
            BY ONLY <1>2, <1>3, <1>4, SMT DEF Single
        <1>7. AuthoredCopyDescriptors(FirstStep, FirstCopy) = {SourceIdentityAction}
            BY ONLY <1>2, <1>3, <1>4, <1>5, <1>6, SMT DEF AuthoredCopyDescriptors, SourceIdentityAction
        <1>. QED BY ONLY <1>1, <1>7, SMT DEF AuthoredCopyDescriptor, Single, FirstStep, FirstCopy
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
