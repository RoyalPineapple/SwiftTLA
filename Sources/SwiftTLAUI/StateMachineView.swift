import SwiftUI
import SwiftTLA

@available(macOS 14, iOS 17, *)
public struct StateMachineView<M: TLAMachine>: View {
    @State private var machine: M
    @State private var stepCount = 0

    public init(machine: M = M.initial) {
        _machine = State(initialValue: machine)
    }

    public var body: some View {
        VStack(spacing: 12) {
            Text("Step \(stepCount)").font(.caption).foregroundStyle(.secondary)
            Text(machine.description)
                .font(.system(.body, design: .monospaced))
                .padding(8).background(.quaternary).clipShape(RoundedRectangle(cornerRadius: 8))
            ForEach(machine.availableTransitions.indices, id: \.self) { i in
                let t = machine.availableTransitions[i]
                Button("\(t)") { machine.apply(t); stepCount += 1 }.buttonStyle(.borderedProminent)
            }
            if machine.availableTransitions.isEmpty { Text("Terminal").foregroundStyle(.secondary) }
            Button("Reset") { machine = M.initial; stepCount = 0 }.buttonStyle(.bordered).tint(.red)
        }.padding(12)
    }
}
