import SwiftUI
import SwiftTLA

@available(macOS 14, iOS 17, *)
public struct StateMachineView<M: TLAMachine>: View {
    @State private var current: M
    @State private var stepCount = 0

    public init(machine: M = M.initial) {
        _current = State(initialValue: machine)
    }

    public var body: some View {
        VStack(spacing: 16) {
            Text("Step: \(stepCount)")
            Text(current.description)
                .font(.largeTitle.monospaced())
                .padding()
                .background(.quaternary)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            ForEach(current.availableActions.indices, id: \.self) { i in
                let action = current.availableActions[i]
                Button("\(action)") {
                    var next = current
                    next.apply(action)
                    current = next
                    stepCount += 1
                }
                .buttonStyle(.borderedProminent)
            }

            if current.availableActions.isEmpty {
                Text("No actions").foregroundStyle(.secondary)
            }

            Button("Reset") {
                current = M.initial
                stepCount = 0
            }
            .buttonStyle(.bordered)
            .tint(.red)
        }
        .padding()
    }
}
