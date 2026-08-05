import SwiftUI
import SwiftTLA

public struct TLAMachineGraphView<Machine: TLAMachine & Hashable>: View {
    public let graph: TLAMachineGraph<Machine>
    public let current: Machine
    @Binding public var selected: Machine?

    public init(graph: TLAMachineGraph<Machine>, current: Machine, selected: Binding<Machine?>) {
        self.graph = graph; self.current = current; _selected = selected
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 4) {
                ForEach(graph.nodes) { node in
                    HStack {
                        Circle()
                            .fill(node.state == current ? .blue : (node.state == selected ? .accentColor : .secondary.opacity(0.2)))
                            .frame(width: 10, height: 10)
                        Text(node.label)
                            .font(.caption.monospaced())
                            .fontWeight(node.state == current ? .bold : .regular)
                            .foregroundStyle(node.state == current ? .primary : .secondary)
                        Spacer()
                        if graph.edges.contains(where: { $0.source == node.state }) {
                            Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(node.state == current ? .blue.opacity(0.1) : (node.state == selected ? .accentColor.opacity(0.05) : .clear))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .onTapGesture { selected = (selected == node.state ? nil : node.state) }
                }
            }
            .padding(8)
        }
    }
}
