import SwiftUI
import SwiftTLAUI

public struct MajorityThemeView: View {
    @State private var machine = Majority.Machine.initial
    public init() {}
    public var body: some View {
        VStack(spacing: 24) {
            HStack(spacing: 32) {
                VStack { Text("Candidate").font(.caption); Text("\(machine.cand)").font(.title.monospaced()).padding(8).background(.quaternary).clipShape(RoundedRectangle(cornerRadius: 8)) }
                VStack { Text("Count").font(.caption); Text("\(machine.cnt)").font(.title.monospaced()).padding(8).background(.quaternary).clipShape(RoundedRectangle(cornerRadius: 8)) }
                VStack { Text("Index").font(.caption); Text("\(machine.i)").font(.title.monospaced()).padding(8).background(.quaternary).clipShape(RoundedRectangle(cornerRadius: 8)) }
            }
            Text("Majority Vote").font(.title.bold())
            Text("Boyer-Moore algorithm. 5 states in this bounded model.")
                .foregroundStyle(.secondary)
            Button("Step") { var m = machine; m.apply(.action_next); machine = m }
                .buttonStyle(.borderedProminent).controlSize(.large)
            Button("Reset") { machine = Majority.Machine.initial }.buttonStyle(.bordered).tint(.red)
        }
        .padding(32)
    }
}
