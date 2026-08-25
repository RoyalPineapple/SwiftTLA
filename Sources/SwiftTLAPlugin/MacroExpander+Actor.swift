import SwiftSyntax
import SwiftTLA

extension MacroExpander {
    static func generateActorMembers(model: MacroCompilation) -> [DeclSyntax] {
        let typeName = model.typeName
        return [
            DeclSyntax(stringLiteral: """
            public actor Actor {
                private var _machine: \(typeName)

                public init() throws {
                    _machine = try \(typeName).makeMachine()
                }

                public var state: State {
                    _machine.state
                }

                public func isEnabled(_ action: Action) throws -> Bool {
                    try _machine.isEnabled(action)
                }

                public func enabledActions() throws -> [Action] {
                    try _machine.enabledActions()
                }

                public func send(_ action: Action) throws -> Transition {
                    try _machine.send(action)
                }
            }
            """)
        ]
    }
}
