import SwiftSyntax
import SwiftTLA

extension TLASpecVerifier {
    static func sourceTypes(
        in members: MemberBlockItemListSyntax,
        enums: [ParsedEnum]
    ) throws -> NativeSourceTypeMetadata {
        let aliases = try members.compactMap { $0.decl.as(TypeAliasDeclSyntax.self) }.reduce(into: [String: String]()) { result, alias in
            guard result.updateValue(alias.initializer.value.trimmedDescription, forKey: alias.name.text) == nil else {
                throw ModelMacroError.unsupportedRecordSchema(typeName: alias.name.text)
            }
        }
        let structs = members.compactMap { $0.decl.as(StructDeclSyntax.self) }
        let enclosingType = members.parent?.parent?.as(StructDeclSyntax.self)?.name.text
        func fieldStorageName(_ type: TypeSyntax) -> String? {
            if let reference = type.as(IdentifierTypeSyntax.self) { return reference.name.text }
            guard let qualified = type.as(MemberTypeSyntax.self),
                  let owner = qualified.baseType.as(IdentifierTypeSyntax.self),
                  owner.name.text == enclosingType else { return nil }
            return qualified.name.text
        }
        let schemas = members.compactMap { $0.decl.as(EnumDeclSyntax.self) }.filter {
            $0.inheritanceClause?.inheritedTypes.contains {
                $0.type.as(IdentifierTypeSyntax.self)?.name.text == "TLARecordSchema"
            } == true
        }
        let records = try schemas.reduce(into: [String: [NativeSourceRecordField]]()) { records, schema in
            let failure = ModelMacroError.unsupportedRecordSchema(typeName: schema.name.text)
            let members = schema.memberBlock.members
            guard let fieldsAlias = members.compactMap({ $0.decl.as(TypeAliasDeclSyntax.self) }).first(where: { $0.name.sourceIdentifierName == "Fields" }),
                  let fieldsName = fieldStorageName(fieldsAlias.initializer.value),
                  let fields = structs.first(where: { $0.name.text == fieldsName }),
                  let nameFunction = members.compactMap({ $0.decl.as(FunctionDeclSyntax.self) }).first(where: { $0.name.sourceIdentifierName == "fieldName" }),
                  let parameter = nameFunction.signature.parameterClause.parameters.first,
                  let body = nameFunction.body else { throw failure }
            let parameterName = parameter.secondName?.text ?? parameter.firstName.text
            let properties = try fields.memberBlock.members.compactMap { $0.decl.as(VariableDeclSyntax.self) }.flatMap { declaration in
                try declaration.bindings.map { binding -> (name: String, swiftType: String) in
                    guard let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.sourceIdentifierName,
                          let type = binding.typeAnnotation?.type, binding.accessorBlock == nil else { throw failure }
                    return (name, type.trimmedDescription)
                }
            }
            var reference = parameterName
            var names: [String: String] = [:]
            for statement in body.statements {
                if let declaration = statement.item.as(VariableDeclSyntax.self),
                   declaration.bindingSpecifier.tokenKind == .keyword(.let), declaration.bindings.count == 1,
                   let binding = declaration.bindings.first,
                   let name = binding.pattern.as(IdentifierPatternSyntax.self)?.identifier.sourceIdentifierName,
                   binding.initializer?.value.tokens(viewMode: .sourceAccurate).map(\.sourceIdentifierName) == [parameterName, "as", "AnyKeyPath"],
                   reference == parameterName {
                    reference = name
                } else if let branch = statement.item.as(IfExprSyntax.self)
                            ?? statement.item.as(ExpressionStmtSyntax.self)?.expression.as(IfExprSyntax.self),
                          branch.elseBody == nil,
                          branch.conditions.count == 1, let condition = branch.conditions.first,
                          branch.body.statements.count == 1,
                          let result = branch.body.statements.first?.item.as(ReturnStmtSyntax.self)?.expression?.as(StringLiteralExprSyntax.self)?.representedLiteralValue,
                          let property = properties.first(where: {
                              condition.tokens(viewMode: .sourceAccurate).map(\.sourceIdentifierName) == [reference, "==", "\\", fieldsName, ".", $0.name]
                          }), names[property.name] == nil {
                    names[property.name] = result
                } else if statement.item.as(ReturnStmtSyntax.self)?.expression?.is(NilLiteralExprSyntax.self) == true {
                    guard statement.id == body.statements.last?.id else { throw failure }
                } else { throw failure }
            }
            guard names.count == properties.count, Set(names.values).count == names.count else { throw failure }
            let bindings = members.compactMap { $0.decl.as(VariableDeclSyntax.self) }.filter {
                $0.modifiers.contains { $0.name.sourceIdentifierName == "static" }
            }.flatMap { Array($0.bindings) }
            guard let fieldList = bindings.first(where: {
                $0.pattern.as(IdentifierPatternSyntax.self)?.identifier.sourceIdentifierName == "fields"
            })?.initializer?.value.as(ArrayExprSyntax.self) else { throw failure }
            let declaredProperties = try fieldList.elements.map { element -> (selector: String, property: String) in
                guard let call = element.expression.as(FunctionCallExprSyntax.self),
                      let field = call.arguments.first?.expression.as(DeclReferenceExprSyntax.self)?.baseName.sourceIdentifierName,
                      let fieldBinding = bindings.first(where: {
                          $0.pattern.as(IdentifierPatternSyntax.self)?.identifier.sourceIdentifierName == field
                      }),
                      let fieldCall = fieldBinding.initializer?.value.as(FunctionCallExprSyntax.self),
                      fieldCall.calledExpression.as(DeclReferenceExprSyntax.self)?.baseName.sourceIdentifierName == "field",
                      fieldCall.arguments.count == 1,
                      let keyPath = fieldCall.arguments.first?.expression,
                      let property = properties.first(where: {
                          keyPath.tokens(viewMode: .sourceAccurate).map(\.sourceIdentifierName) == ["\\", fieldsName, ".", $0.name]
                      }) else { throw failure }
                return (field, property.name)
            }
            guard Set(declaredProperties.map(\.property)).count == declaredProperties.count else { throw failure }
            records[schema.name.text] = declaredProperties.map { field in
                NativeSourceRecordField(sourceName: field.selector, name: names[field.property]!, swiftType: properties.first { $0.name == field.property }!.swiftType)
            }
        }
        let finiteTypes = Set(members.compactMap { $0.decl.as(EnumDeclSyntax.self) }.filter { declaration in
            declaration.inheritanceClause?.inheritedTypes.contains {
                $0.type.as(IdentifierTypeSyntax.self)?.name.text == "FiniteTLAValueDomain"
            } == true
        }.map { $0.name.text })
        return NativeSourceTypeMetadata(
            aliases: aliases,
            records: records,
            enums: Dictionary(uniqueKeysWithValues: enums.map { ($0.typeName, $0.cases.map(\.value)) }),
            finiteViewDomains: Dictionary(uniqueKeysWithValues: enums.filter { finiteTypes.contains($0.typeName) }.map {
                ($0.typeName, $0.formalDomainValues)
            })
        )
    }
}
