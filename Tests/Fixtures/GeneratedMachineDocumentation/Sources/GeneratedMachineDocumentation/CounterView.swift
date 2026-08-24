// Example ID: generated-machine-swiftui

import SwiftTLA
import SwiftUI

struct CounterView: View {
    @State private var machine: CounterScreenModel?
    @State private var diagnostic = ""

    var body: some View {
        VStack {
            Text("Value: \(machine.map { String($0.state.value) } ?? "-")")
            Button("Advance") {
                do {
                    guard var machine else { return }
                    try machine.send(.advance)
                    self.machine = machine
                    diagnostic = ""
                } catch {
                    diagnostic = String(describing: error)
                }
            }
            .disabled(canAdvance == false)
            if !diagnostic.isEmpty {
                Text(diagnostic)
            }
        }
        .task {
            guard machine == nil else { return }
            do {
                machine = try CounterScreenModel.makeMachine()
            } catch {
                diagnostic = String(describing: error)
            }
        }
    }

    private var canAdvance: Bool {
        guard let machine else { return false }
        return (try? machine.isEnabled(.advance)) == true
    }
}
