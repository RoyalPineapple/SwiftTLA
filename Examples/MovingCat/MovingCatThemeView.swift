import SwiftUI
import SwiftTLAUI

public struct MovingCatThemeView: View {
    @State private var machine = MovingCat.Machine.initial
    public init() {}
    public var body: some View {
        VStack(spacing: 24) {
            HStack(spacing: 4) {
                ForEach(1...6, id: \.self) { i in
                    ZStack {
                        Rectangle().stroke().frame(width: 44, height: 44)
                        if i == machine.cat { Image(systemName: "cat.fill").font(.title2) }
                        else if i == machine.observed { Image(systemName: "eye.fill").font(.title2).foregroundStyle(.blue) }
                    }
                }
            }
            Text("Moving Cat").font(.title.bold())
            Text("Find the cat. Cat moves ±1 nightly, you check each morning. 70 states.")
                .foregroundStyle(.secondary)
            Button("Step") { var m = machine; m.apply(.action_next); machine = m }
                .buttonStyle(.borderedProminent).controlSize(.large)
            Button("Reset") { machine = MovingCat.Machine.initial }.buttonStyle(.bordered).tint(.red)
        }
        .padding(32)
    }
}
