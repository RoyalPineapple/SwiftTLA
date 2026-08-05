import Foundation
import SwiftTLA

public struct ViewGenerator {
    public let graph: StateGraph
    public init(graph: StateGraph) { self.graph = graph }

    public func generate() -> String {
        let specName = graph.specName.replacingOccurrences(of: " ", with: "")
        let varNames = graph.variableNames
        let stateDesc = varNames.map { v in "\"\(v): \\(machine.\(v))\"" }.joined(separator: " + \"\\n\" + ")

        return """
        import SwiftUI
        import SwiftTLA

        public struct \(specName)DemoView: View {
            @State private var machine = \(specName).Machine.initial

            public init() {}

            public var body: some View {
                StateMachineView(machine: machine)
            }
        }
        """
    }
}
