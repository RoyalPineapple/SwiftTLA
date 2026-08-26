import SwiftSyntax
import SwiftTLA

extension MacroExpander {
    static func generateActorMembers(model: MacroCompilation) -> [DeclSyntax] {
        let typeName = model.typeName
        let actionMembers = model.compilation.machineSurfacePlan.actions.isEmpty ? "" : """

                public func isEnabled(_ action: Action) throws -> Bool {
                    try machine.isEnabled(action)
                }

                public func enabledActions() throws -> [Action] {
                    try machine.enabledActions()
                }

                public func send(_ action: Action) throws -> Transition {
                    try machine.send(action)
                }
                """
        return [
            DeclSyntax(stringLiteral: """
            public actor Actor {
                private var machine: \(typeName)

                public init() throws {
                    machine = try \(typeName).makeMachine()
                }

                public init(_ initial: State) throws {
                    machine = try \(typeName).makeMachine(initial)
                }

                public var state: State {
                    machine.state
                }

                \(actionMembers)
            }
            """)
        ]
    }
}
