import SwiftParser
import SwiftSyntax
import SwiftTLA

private func nativeProjectionTokens(_ syntax: some SyntaxProtocol) -> [[UInt8]] {
    syntax.tokens(viewMode: .sourceAccurate).map { Array($0.text.utf8) }
}
private func nativeProjectionMismatch(_ reason: String) -> CompilationDiagnostic {
    CompilationDiagnostic(
        code: .unsupportedGeneratedValueShape, stage: .validation,
        path: "native.formalProjection",
        expected: "one ordered formal entry from each complete snapshot field",
        actual: reason,
        nextSafeAction: "Report this native code generation failure."
    )
}
package func verifyGeneratedFormalProjectionTokenTable(_ declaration: DeclSyntax?, names: [String]) throws {
    let tokenValues = names.map {
        "SwiftTLA._nativeFormalProjectionToken(validating: \(String(reflecting: $0)))!"
    }.joined(separator: ", ")
    let expectedTokens = Parser.parse(source: """
    private static let __swifttlaFormalProjectionTokens: [SwiftTLA.TLAStateProjection.Token] = [\(tokenValues)]
    """).statements.first?.item
    guard let declaration, let expectedTokens,
          nativeProjectionTokens(declaration) == nativeProjectionTokens(expectedTokens) else {
        throw nativeProjectionMismatch("the formal state token list differs from the compiled variable names")
    }
}

package func verifyGeneratedFormalProjectionOutput(
    _ declarations: [DeclSyntax], fields: [(formalName: String, route: String, type: CompiledValueType, value: String)]
) throws {
    guard declarations.count == 2 else {
        throw nativeProjectionMismatch("the formal state token list differs from the compiled variable names")
    }
    try verifyGeneratedFormalProjectionTokenTable(declarations[0], names: fields.map(\.formalName))
    for field in fields {
        let expectedRoute = Parser.parse(source: field.route).statements.first?.item
        let value = Parser.parse(source: field.value).statements.first?.item
        guard let expectedRoute, let value else { throw nativeProjectionMismatch("the projected value cannot be parsed") }
        let route = nativeProjectionTokens(expectedRoute)
        let valueTokens = nativeProjectionTokens(value)
        let references = valueTokens.indices.filter { valueTokens[$0] == Array("snapshot".utf8) }
        guard !references.isEmpty, references.allSatisfy({ index in
            index + route.count <= valueTokens.count
                && Array(valueTokens[index..<(index + route.count)]) == route
        }) else { throw nativeProjectionMismatch("the projected value for \(field.formalName) reads a different snapshot field") }
        if field.type == .int {
            let expected = Parser.parse(source: "SwiftTLA._nativeFormalInt(\(field.route))").statements.first?.item
            guard let expected, valueTokens == nativeProjectionTokens(expected) else {
                throw nativeProjectionMismatch("the projected Int value for \(field.formalName) does not use the library integer conversion")
            }
        }
    }
    let expectedEntries = fields.enumerated().map { index, field in
        "SwiftTLA._nativeFormalProjectionEntry(Self.__swifttlaFormalProjectionTokens, at: \(index), value: \(field.value))"
    }.joined(separator: ",\n")
    let expectedFunction = Parser.parse(source: """
    public func formalProjection(of snapshot: Snapshot) throws -> SwiftTLA.TLAStateProjection {
        try SwiftTLA._nativeFormalProjection([\(expectedEntries)])
    }
    """).statements.first?.item
    guard let expectedFunction, nativeProjectionTokens(declarations[1]) == nativeProjectionTokens(expectedFunction) else {
        throw nativeProjectionMismatch("the projection call shape or formal token ordering differs from the checked rule")
    }
}

/// Each field read belongs to exactly one token, in the original projection order.
package func verifyGeneratedFormalProjectionVisits(_ walk: DeclSyntax, routes: [String], readers: [String], types: [CompiledValueType]) throws {
    guard let body = walk.as(FunctionDeclSyntax.self)?.body, routes.count == readers.count, routes.count == types.count else {
        throw nativeProjectionMismatch("missing typed field traversal")
    }
    let helpers = body.statements.compactMap { $0.item.as(FunctionDeclSyntax.self) }
    let integer = nativeProjectionTokens(Parser.parse(source: "try out.projected(SwiftTLA._nativeFormalInt(value))").statements)
    for (reader, type) in zip(readers, types) where type == .int {
        guard let implementation = helpers.first(where: { $0.name.text == reader })?.body,
              nativeProjectionTokens(implementation.statements) == integer else {
            throw nativeProjectionMismatch("the typed traversal changes the projected Int value")
        }
    }
    let statements = body.statements.filter { !$0.item.is(FunctionDeclSyntax.self) }
    let expected = routes.enumerated().map { index, route in
        "try sink.field(SwiftTLA._nativeFormalProjectionToken(Self.__swifttlaFormalProjectionTokens, at: \(index)), \(route), \(readers[index]))"
    } + ["return true"]
    guard statements.count == expected.count,
          zip(statements, expected).allSatisfy({ nativeProjectionTokens($0.0) == nativeProjectionTokens(Parser.parse(source: $0.1).statements) }),
          body.statements.filter({ $0.item.is(FunctionDeclSyntax.self) })
            .allSatisfy({ !nativeProjectionTokens($0).contains(Array("snapshot".utf8)) }) else {
        throw nativeProjectionMismatch("the typed traversal differs from the compiled snapshot field order or route")
    }
}
