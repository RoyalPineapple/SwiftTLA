import SwiftUI
import SwiftTLA

@available(macOS 14, iOS 17, *)
public struct StateMachineView<M: TLAMachine>: View {
    @State private var current: M
    @State private var stepCount = 0
    @State private var trace: [String] = []

    public init(machine: M = M.initial) {
        _current = State(initialValue: machine)
    }

    public var body: some View {
        VStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("State \(stepCount)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(current.description)
                    .font(.system(.body, design: .monospaced))
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            Text("Available: \(current.availableActions.count) actions")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(Array(current.availableActions.enumerated()), id: \.offset) { i, action in
                Button {
                    var next = current
                    next.apply(action)
                    current = next
                    stepCount += 1
                    trace.append(String(describing: action))
                } label: {
                    Label(String(describing: action), systemImage: "arrow.right.circle.fill")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderedProminent)
                .tint(.accentColor)
            }

            if current.availableActions.isEmpty {
                Label("Terminal state", systemImage: "stop.circle.fill")
                    .foregroundStyle(.secondary)
            }

            if !trace.isEmpty {
                ScrollView(.horizontal) {
                    Text(trace.joined(separator: " → "))
                        .font(.caption.monospaced())
                }
                Button("Reset", systemImage: "arrow.counterclockwise") {
                    current = M.initial
                    stepCount = 0
                    trace = []
                }
                .buttonStyle(.borderedProminent).tint(.red)
            }
        }
    }
}
