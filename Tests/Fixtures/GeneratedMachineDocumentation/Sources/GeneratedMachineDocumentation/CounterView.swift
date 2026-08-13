// Example ID: generated-machine-swiftui

import SwiftTLA
import SwiftUI

struct CounterView: View {
    @State private var machine = CounterScreenModel.Observable()
    @State private var observation = TLAMachineObservation(
        state: [:],
        availability: .available([])
    )
    @State private var diagnostic = ""

    var body: some View {
        VStack {
            Text("Value: \(observation.state["value"]?.description ?? "-")")
            Button("Advance") {
                Task { @MainActor in
                    do {
                        _ = try await machine.execute(.init(name: "advance"))
                        observation = await machine.machineObservation()
                        diagnostic = ""
                    } catch {
                        diagnostic = String(describing: error)
                    }
                }
            }
            if let invocations = observation.availableInvocations {
                ForEach(invocations, id: \.self) { invocation in
                    Text(invocation.description)
                }
            } else if let diagnostic = observation.availabilityDiagnostic {
                Text(diagnostic.message)
            }
            if !diagnostic.isEmpty {
                Text(diagnostic)
            }
        }
        .task { observation = await machine.machineObservation() }
    }
}
