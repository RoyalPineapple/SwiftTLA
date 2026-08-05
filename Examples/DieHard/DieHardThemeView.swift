import SwiftUI
import SwiftTLAUI

public struct DieHardThemeView: View {
    @State private var machine = DieHard.StateMachine.initial
    @State private var lastAction = ""

    public init() {}
    public var body: some View {
        VStack(spacing: 24) {
            HStack(alignment: .bottom, spacing: 32) {
                VStack {
                    Text("Big Jug").font(.caption)
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 8).stroke().frame(height: 140)
                        Rectangle().fill(.blue.gradient)
                            .frame(height: CGFloat(machine.big) / 5 * 138)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .frame(width: 70)
                    Text("\(machine.big)/5").font(.caption.monospaced())
                }
                VStack {
                    Text("Small Jug").font(.caption)
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 8).stroke().frame(height: 90)
                        Rectangle().fill(.cyan.gradient)
                            .frame(height: CGFloat(machine.small) / 3 * 88)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .frame(width: 70)
                    Text("\(machine.small)/3").font(.caption.monospaced())
                }
            }

            Text("Die Hard Puzzle").font(.title.bold())
            Text("Measure 4 gallons. \(lastAction)").foregroundStyle(.secondary)

            HStack(spacing: 8) { Button("Fill Big") { apply(.fillBigJug) }; Button("Empty Big") { apply(.emptyBigJug) } }
            HStack(spacing: 8) { Button("Fill Small") { apply(.fillSmallJug) }; Button("Empty Small") { apply(.emptySmallJug) } }
            HStack(spacing: 8) { Button("Small → Big") { apply(.smallToBig) }; Button("Big → Small") { apply(.bigToSmall) } }
            Button("Reset") { machine = DieHard.StateMachine.initial; lastAction = "" }.buttonStyle(.bordered).tint(.red)
        }
        .padding(32)
        .buttonStyle(.bordered)
    }

    private func apply(_ action: DieHard.StateMachine.Transition) { var m = machine; m.apply(action); machine = m; lastAction = action.rawValue }
}
