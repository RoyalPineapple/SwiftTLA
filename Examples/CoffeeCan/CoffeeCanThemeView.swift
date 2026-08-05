import SwiftUI
import SwiftTLAUI

public struct CoffeeCanThemeView: View {
    @State private var machine = CoffeeCan.StateMachine.initial
    public init() {}
    public var body: some View {
        VStack(spacing: 24) {
            HStack(spacing: 32) {
                VStack {
                    Text("Black").font(.caption)
                    HStack(spacing: 2) { ForEach(0..<machine.black, id: \.self) { _ in Circle().fill(.black).frame(width: 12, height: 12) } }
                    Text("\(machine.black)").font(.title3.monospaced())
                }
                VStack {
                    Text("White").font(.caption)
                    HStack(spacing: 2) { ForEach(0..<machine.white, id: \.self) { _ in Circle().stroke().frame(width: 12, height: 12) } }
                    Text("\(machine.white)").font(.title3.monospaced())
                }
            }
            Text("Coffee Can").font(.title.bold())
            Text("Remove beans per rules. 36 states, eventual deadlock.")
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Button("Two Black") { apply(.pickSameColorBlack) }
                Button("Two White") { apply(.pickSameColorWhite) }
                Button("One Each") { apply(.pickDifferentColor) }
            }
            Button("Reset") { machine = CoffeeCan.StateMachine.initial }.buttonStyle(.bordered).tint(.red)
        }
        .padding(32)
        .buttonStyle(.bordered)
    }
    private func apply(_ action: CoffeeCan.StateMachine.Transition) { var m = machine; m.apply(action); machine = m }
}
