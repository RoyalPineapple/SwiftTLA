import SwiftUI
import SwiftTLA

public struct TLAMachineInspector<Machine: TLAMachine & Hashable>: View {
    @Binding var machine: Machine
    @State private var history: [String] = []

    public init(machine: Binding<Machine>) {
        _machine = machine
    }

    public var body: some View {
        HSplitView {
            summaryPanel.frame(minWidth: 200, idealWidth: 250)
            listPanel.frame(minWidth: 200, idealWidth: 250)
        }
    }

    private var summaryPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Inspector").font(.headline)
            Text(machine.description).font(.title3.monospaced())
                .padding(8).background(.quaternary).clipShape(RoundedRectangle(cornerRadius: 8))

            let actions = machine.availableTransitions
            if actions.isEmpty {
                Text("Terminal").foregroundStyle(.secondary)
            } else {
                ForEach(actions, id: \.self) { t in
                    Button("\(t)") {
                        machine.apply(t)
                        history.append("\(t)")
                    }.buttonStyle(.borderedProminent)
                }
            }

            if !history.isEmpty {
                Text(history.joined(separator: " → ")).font(.caption.monospaced())
                Button("Reset") { machine = Machine.initial; history = [] }.buttonStyle(.bordered).tint(.red)
            }
        }.padding()
    }

    private var listPanel: some View {
        VStack {
            Text("Transitions").font(.headline).padding(.top, 8)
            List {
                ForEach(machine.availableTransitions, id: \.self) { t in
                    LabeledContent("\(t)", value: destination(t).description)
                }
            }
        }
        .background(.regularMaterial)
    }

    private func destination(_ t: Machine.Transition) -> Machine {
        var d = machine; d.apply(t); return d
    }
}
