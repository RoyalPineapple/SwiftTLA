import Foundation
import SwiftTLA

public struct ViewModelGenerator {
    private let specification: TLASpec

    public init(spec: TLASpec) {
        self.specification = spec
    }

    public func generate() -> String {
        let typeName = specification.name
        let stateProperties = specification.variables.map { variable in
            "    public var " + variable.name + ": Int { machine." + variable.name + " }"
        }.joined(separator: "\n")

        let actionMethods = specification.actions.map { action in
            let lowercased = lowered(action.name)
            return "    public func " + lowercased + "() { machine.apply(." + lowercased + ") }"
        }.joined(separator: "\n")

        let canProperties = specification.actions.map { action in
            let lowercased = lowered(action.name)
            return "    public var can" + action.name
                + ": Bool { machine.availableTransitions.contains(." + lowercased + ") }"
        }.joined(separator: "\n")

        return "import Observation\n\n@Observable public final class ViewModel {\n"
            + "    public var machine: " + typeName + ".StateMachine\n"
            + "    public init(_ machine: " + typeName + ".StateMachine = "
            + typeName + ".StateMachine.initial) { self.machine = machine }\n\n"
            + stateProperties + "\n\n" + actionMethods + "\n\n" + canProperties + "\n}\n"
    }

    private func lowered(_ name: String) -> String {
        name.prefix(1).lowercased() + name.dropFirst()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "_")
    }
}
