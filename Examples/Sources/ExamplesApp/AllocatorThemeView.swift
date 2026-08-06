import SwiftUI
import SwiftTLAUI

public struct AllocatorThemeView: View {
    @State private var machine = Allocator.StateMachine.initial
    public init() {}
    public var body: some View {
        VStack(spacing: 24) {
            HStack(spacing: 32) {
                VStack {
                    Text("Available").font(.caption)
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4).fill(.quaternary).frame(width: 120, height: 28)
                        RoundedRectangle(cornerRadius: 4).fill(.green.gradient).frame(width: CGFloat(machine.available)/3*120, height: 28)
                    }
                    Text("\(machine.available)/3").font(.caption.monospaced())
                }
                VStack {
                    Text("Allocated").font(.caption)
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4).fill(.quaternary).frame(width: 120, height: 28)
                        RoundedRectangle(cornerRadius: 4).fill(.orange.gradient).frame(width: CGFloat(machine.allocated)/3*120, height: 28)
                    }
                    Text("\(machine.allocated)/3").font(.caption.monospaced())
                }
            }
            Text("Total: \(machine.available + machine.allocated)").font(.caption).foregroundStyle(.secondary)

            Text("Resource Allocator").font(.title.bold())
            Text("Allocate and free. Invariant: available + allocated = 3. 4 states.")
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Button("Allocate") { apply(.allocate) }
                Button("Deallocate") { apply(.deallocate) }
            }
            Button("Reset") { machine = Allocator.StateMachine.initial }.buttonStyle(.bordered).tint(.red)
        }
        .padding(32)
        .buttonStyle(.bordered)
    }
    private func apply(_ action: Allocator.StateMachine.Transition) { var m = machine; m.apply(action); machine = m }
}
