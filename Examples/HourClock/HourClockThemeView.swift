import SwiftUI
import SwiftTLAUI

public struct HourClockThemeView: View {
    @State private var machine = HourClock.Machine.initial
    @State private var ticks = 0

    public init() {}
    public var body: some View {
        VStack(spacing: 24) {
            Text("\(machine.hr)")
                .font(.system(size: 96, design: .monospaced))
                .contentTransition(.numericText())
                .padding(24)
                .background(Circle().stroke(lineWidth: 4).frame(width: 160, height: 160))

            Text("Hour Clock").font(.title.bold())
            Text("12 states, \(ticks) ticks").foregroundStyle(.secondary)

            Button("Tick") { var m = machine; m.apply(.hCnxt); machine = m; ticks += 1 }
                .buttonStyle(.borderedProminent).controlSize(.large)
            Button("Reset") { machine = HourClock.Machine.initial; ticks = 0 }
        }
        .padding(32)
    }
}
