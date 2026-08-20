// Example ID: generated-machine-swiftui

import SwiftTLA
import SwiftUI

struct CounterView: View {
    @State private var live: CounterScreenModel.Live?
    @State private var machine: CounterScreenModel.Observable?
    @State private var diagnostic = ""

    var body: some View {
        VStack {
            Text("Value: \(machine?.state.map { String($0.value) } ?? "-")")
            Button("Advance") {
                Task { @MainActor in
                    guard let machine else { return }
                    do {
                        switch try await machine.apply(.advance) {
                        case .committed:
                            diagnostic = ""
                        case .rejected(let rejection):
                            diagnostic = rejection.reason.description
                        case .failed(let failure):
                            diagnostic = failure.message
                        }
                    } catch {
                        diagnostic = String(describing: error)
                    }
                }
            }
            if !diagnostic.isEmpty {
                Text(diagnostic)
            }
        }
        .task {
            guard live == nil else { return }
            do {
                let live = try CounterScreenModel.makeLive()
                self.live = live
                machine = try await CounterScreenModel.Observable(live: live)
            } catch {
                diagnostic = String(describing: error)
            }
        }
    }
}
