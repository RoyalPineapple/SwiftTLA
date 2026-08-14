// Example ID: generated-machine-swiftui

import SwiftTLA
import SwiftUI

struct CounterView: View {
    @State private var machine = CounterScreenModel.Observable()
    @State private var state: CounterScreenModel.State?
    @State private var observation: TLAMachineObservation?
    @State private var diagnostic = ""

    var body: some View {
        VStack {
            Text("Value: \(state.map { String($0.value) } ?? "-")")
            Button("Advance") {
                Task { @MainActor in
                    do {
                        _ = try await machine.execute(CounterScreenModel.Observable.ActionLabel.advance(process: .only).toInvocation())
                        state = machine.state
                        observation = await machine.machineObservation()
                        diagnostic = ""
                    } catch {
                        diagnostic = String(describing: error)
                    }
                }
            }
            if let invocations = observation?.availableInvocations {
                ForEach(invocations, id: \.self) { invocation in
                    Text(invocation.description)
                }
            } else if let diagnostic = observation?.availabilityDiagnostic {
                Text(diagnostic.message)
            }
            if !diagnostic.isEmpty {
                Text(diagnostic)
            }
        }
        .task {
            state = machine.state
            observation = await machine.machineObservation()
        }
    }
}
