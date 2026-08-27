import SwiftUI

struct ClockView: View {
    @State private var machine: ClockModel?
    @State private var diagnostic = ""

    var body: some View {
        VStack {
            if let machine {
                Text("Time: \(machine.state.hour):\(machine.state.minute):\(machine.state.second)")
                Button("Tick") {
                    do {
                        var machine = machine
                        _ = try machine.send(.tick)
                        self.machine = machine
                        diagnostic = ""
                    } catch {
                        diagnostic = String(describing: error)
                    }
                }
            } else {
                ProgressView()
            }

            if diagnostic.isEmpty == false {
                Text(diagnostic)
            }
        }
        .task {
            guard machine == nil else { return }
            do {
                machine = try ClockModel.makeMachine(
                    .init(hour: 16, minute: 19, second: 59)
                )
            } catch {
                diagnostic = String(describing: error)
            }
        }
    }
}
