import Foundation

enum StraightLineRenderedActionCheck {
    private enum Task {
        case action(CompiledActionExpr)
        case value(CompiledExpression)
        case token(String)
    }

    private static let tokenPattern = try? NSRegularExpression(
        pattern: #"\s+|==|/\\|[()]|=|[A-Za-z_][A-Za-z0-9_]*'?|-?[0-9]+"#)

    static func verify(_ action: CompiledActionExpr, rendered: String,
                       layout: CompiledLayout, binders: [BinderID: String]) throws {
        let variables = Dictionary(uniqueKeysWithValues: layout.variables.map {
            ($0.id, $0.declaration.name)
        })
        func mismatch() -> CompilationDiagnostic {
            CompilationDiagnostic(
                code: .unsupportedGeneratedValueShape, stage: .validation,
                path: "tla.action.scalarAssignments",
                expected: "the complete TLA+ action form for the compiled scalar assignment rule",
                actual: "the emitted action body differs from its compiled identities and values",
                nextSafeAction: "Report this TLA+ action emission failure."
            )
        }
        var expected: [String] = []
        var usedBinderNames: Set<String> = []
        var pending: [Task] = [.action(action)]
        func schedule(_ tasks: [Task]) { pending.append(contentsOf: tasks.reversed()) }
        while let task = pending.popLast() {
            switch task {
            case .token(let token): expected.append(token)
            case .value(let expression):
                guard expression.children.isEmpty else { return }
                switch expression.operation {
                case .stateVariable(let id):
                    guard let name = variables[id] else { throw mismatch() }
                    expected.append(name)
                case .boundValue(let id):
                    guard let name = binders[id] else { throw mismatch() }
                    expected.append(name)
                case .value(.integer(let value)): expected.append(String(value))
                case .value(.boolean(let value)): expected.append(value ? "TRUE" : "FALSE")
                default: return
                }
            case .action(let node):
                switch node {
                case .assign(let id, let value):
                    guard let name = variables[id] else { throw mismatch() }
                    schedule([.token("\(name)'"), .token("="), .value(value)])
                case .unchanged(let id):
                    guard let name = variables[id] else { throw mismatch() }
                    schedule([.token("UNCHANGED"), .token(name)])
                case .guard_(let value):
                    guard value.children.isEmpty,
                          value.operation == .value(.boolean(true)) else { return }
                    expected.append("TRUE")
                case .define(let id, let value, let body):
                    guard let name = binders[id], isFormalIdentifier(name),
                          !variables.values.contains(name),
                          usedBinderNames.insert(name).inserted else { return }
                    schedule([.token("("), .token("LET"), .token(name), .token("=="),
                        .value(value), .token("IN"), .action(body), .token(")")])
                case .and(let left, let right):
                    schedule([.token("("), .action(left), .token("/\\"), .action(right), .token(")")])
                default: return
                }
            }
        }
        guard let actual = tokens(rendered), actual == expected else { throw mismatch() }
    }

    private static func tokens(_ source: String) -> [String]? {
        guard let tokenPattern else { return nil }
        let text = source as NSString
        var offset = 0
        var result: [String] = []
        while offset < text.length {
            guard let match = tokenPattern.firstMatch(in: source,
                    range: NSRange(location: offset, length: text.length - offset)),
                  match.range.location == offset else { return nil }
            let token = text.substring(with: match.range)
            if token.first?.isWhitespace == false { result.append(token) }
            offset = match.range.upperBound
        }
        return result
    }
}
