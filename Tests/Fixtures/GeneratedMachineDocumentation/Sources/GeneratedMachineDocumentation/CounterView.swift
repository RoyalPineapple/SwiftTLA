// Example ID: generated-machine-swiftui

import SwiftTLA
import SwiftUI

struct CounterView: View {
    @State private var owner: TLALiveMachineOwner?
    @State private var machine: CounterScreenModel.Observable?
    @State private var diagnostic = ""

    var body: some View {
        VStack {
            Text("Value: \(machine?.state.map { String($0.value) } ?? "-")")
            Button("Advance") {
                Task { @MainActor in
                    guard let machine else { return }
                    do {
                        switch try await machine._advance() {
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
            guard owner == nil else { return }
            do {
                let owner = try CounterScreenModel.makeLiveOwner()
                self.owner = owner
                machine = try await CounterScreenModel.Observable(handle: owner.handle)
            } catch {
                diagnostic = String(describing: error)
            }
        }
    }
}
