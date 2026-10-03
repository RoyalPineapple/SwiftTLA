import SwiftTLA
import Foundation
import SwiftParser
import SwiftSyntax

/// Swift names and parameters exposed by the generated machine.
package struct GeneratedMachineAPI: Sendable, Equatable {
    package struct Variable: Sendable, Equatable {
        package let swiftIdentifier: String
        package var argumentLabel: String { swiftIdentifier.replacingOccurrences(of: "`", with: "") }
        package let id: VariableID
        init(formalName: String, id: VariableID) throws {
            self.swiftIdentifier = try GeneratedMachineAPI.sourceIdentifier(formalName)
            self.id = id
        }
    }

    package struct Binding: Sendable, Equatable {
        package let swiftIdentifier: String
        package let isPublic: Bool

        init(formalName: String, isPublic: Bool) throws {
            self.swiftIdentifier = try GeneratedMachineAPI.sourceIdentifier(formalName)
            self.isPublic = isPublic
        }
    }

    package struct Action: Sendable, Equatable {
        package let compiledAction: ActionID
        package let swiftIdentifier: String
        package let bindings: [Binding]
    }

    package let variables: [Variable]
    package let actions: [Action]

    init(layout: CompiledLayout, actions: [CompiledAction]) throws {
        let variables = try layout.variables.filter {
            $0.declaration.origin == .source
        }.map { variable in
            return try Variable(
                formalName: variable.declaration.name,
                id: variable.id
            )
        }
        let actionIdentifiers = Self.generatedIdentifiers(layout.actions.map(\.declaration.name), fallback: "action")
        let compiledActions = Dictionary(uniqueKeysWithValues: actions.map { ($0.id, $0) })
        let actions = try zip(layout.actions, actionIdentifiers).map { layoutAction, identifier in
            guard let action = compiledActions[layoutAction.id] else {
                throw Self.missingDeclaration("action", named: layoutAction.declaration.name)
            }
            return Action(
                compiledAction: layoutAction.id,
                swiftIdentifier: identifier,
                bindings: try action.bindings.map { binding in
                    try Binding(
                        formalName: binding.sourceName,
                        isPublic: binding.literalMembers?.count != 1
                    )
                }
            )
        }

        self.variables = variables
        self.actions = actions
    }

    private static func missingDeclaration(_ kind: String, named name: String) -> CompilationDiagnostic {
        CompilationDiagnostic(
            code: .compilationIdentityMismatch,
            stage: .lowering,
            path: "machineSurfacePlan.\(kind).\(name)",
            expected: "a declaration in the compiled layout",
            actual: "no matching declaration identity",
            nextSafeAction: "Compile the model again from its current source."
        )
    }

    private static func sourceIdentifier(_ name: String) throws -> String {
        let tokens = Parser.parse(source: name).tokens(viewMode: .sourceAccurate).filter {
            $0.tokenKind != .endOfFile
        }
        guard tokens.count == 1, let token = tokens.first, token.text == name, name != "_" else {
            throw invalidSourceIdentifier(name)
        }
        switch token.tokenKind {
        case .identifier: return name
        case .keyword: return "`\(name)`"
        default: throw invalidSourceIdentifier(name)
        }
    }

    private static func invalidSourceIdentifier(_ name: String) -> CompilationDiagnostic {
        CompilationDiagnostic(
            code: .unsupportedGeneratedValueShape,
            stage: .validation,
            path: "generatedMachineAPI.identifiers.\(name)",
            expected: "one named Swift identifier for a generated state field or action parameter",
            actual: name,
            nextSafeAction: "Choose a named Swift identifier; formal action labels may use arbitrary names."
        )
    }

    static func generatedIdentifiers(_ names: [String], fallback: String) -> [String] {
        let reserved: Set<String> = ["_", "init", "deinit", "subscript", "rawValue"]
        var used: Set<String> = []
        return names.map { name in
            let scalars = name.unicodeScalars.map { scalar -> Character in
                switch scalar.value {
                case 65...90, 97...122, 48...57, 95: Character(String(scalar))
                default: "_"
                }
            }
            var base = String(scalars)
            if base.isEmpty { base = fallback }
            if base.unicodeScalars.first.map({ (48...57).contains($0.value) }) == true || reserved.contains(base) {
                base = "\(fallback)_\(base)"
            }
            var identifier = base
            var suffix = 2
            while used.contains(identifier) {
                identifier = "\(base)_\(suffix)"
                suffix += 1
            }
            used.insert(identifier)
            if let token = Parser.parse(source: identifier).firstToken(viewMode: .sourceAccurate),
               case .keyword = token.tokenKind {
                return "`\(identifier)`"
            }
            return identifier
        }
    }
}
