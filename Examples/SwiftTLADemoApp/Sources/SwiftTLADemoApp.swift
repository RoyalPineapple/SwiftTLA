import AppKit
import SwiftUI
import SwiftTLA
import SwiftTLADemos

@main
struct SwiftTLADemoApp: App {
    init() {
        DispatchQueue.main.async {
            NSApplication.shared.setActivationPolicy(.regular)
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }

    var body: some Scene {
        WindowGroup("SwiftTLA Demonstrations") {
            DemoHomeView()
                .frame(minWidth: 940, minHeight: 700)
                .preferredColorScheme(.dark)
        }
    }
}

private struct DemoHomeView: View {
    var body: some View {
        TabView {
            TwoBucketsView()
                .tabItem { Text("Two Buckets") }
            DuckDuckLeaderView()
                .tabItem { Text("Duck, Duck, Leader") }
            ElevatorBankView()
                .tabItem { Text("Elevator Bank") }
            GeneratedSurfaceView()
                .tabItem { Text("Generated Tests") }
        }
        .padding(24)
        .background(Color.black.opacity(0.9))
    }
}

private struct TwoBucketsView: View {
    @State private var machine: TwoBuckets?
    @State private var error: String?

    var body: some View {
        DemoScreen(title: "Two Buckets", subtitle: "Measure exactly 4 gallons.") {
            if let machine {
                TwoBucketsScene(state: machine.state, error: error)
                TwoBucketsControls(
                    fillThree: { perform(.fillThree) },
                    emptyThree: { perform(.emptyThree) },
                    pourThreeIntoFive: { perform(.pourThreeIntoFive) },
                    pourFiveIntoThree: { perform(.pourFiveIntoThree) },
                    fillFive: { perform(.fillFive) },
                    emptyFive: { perform(.emptyFive) },
                    enabledActions: availableActions,
                    reset: reset
                )
            } else {
                StateCard(title: "Machine unavailable", detail: "The generated machine could not start.", error: error)
                    .frame(maxWidth: .infinity, minHeight: 430)
            }
        }
        .task { reset() }
    }

    private func reset() {
        do {
            let machine = try TwoBuckets.makeMachine()
            self.machine = machine
            error = nil
        } catch let failure {
            machine = nil
            error = failure.localizedDescription
        }
    }

    private func perform(_ action: TwoBuckets.Action) {
        guard var machine else { return }
        do {
            _ = try machine.send(action)
            self.machine = machine
            error = nil
        }
        catch let failure { error = failure.localizedDescription }
    }

    private var availableActions: Set<TwoBuckets.Action> {
        guard let machine else { return [] }
        return (try? Set(machine.enabledActions())) ?? []
    }
}

private struct DuckDuckLeaderView: View {
    @State private var machine: ChangRoberts?
    @State private var error: String?
    @State private var delivery: DuckDelivery?
    @State private var isDelivering = false
    @State private var isPlaying = false
    @State private var deliveryOrder: [ChangRoberts.Node] = ChangRoberts.Node.all.members
    @State private var lastMove = "Press Play to begin the election."
    @State private var simulationID = UUID()

    private let ring: [ChangRoberts.Node] = [.one, .two, .three, .four, .five, .six, .seven, .eight, .nine, .ten, .eleven, .twelve]

    var body: some View {
        DemoScreen(
            title: "Duck, Duck, Leader",
            subtitle: "A message carrying the largest identifier completes the ring."
        ) {
            if let machine {
                DuckDuckLeaderScene(
                    nodes: ring,
                    state: machine.state,
                    delivery: delivery,
                    lastMove: lastMove,
                    messageStatus: messageStatus,
                    error: error
                )
            } else {
                StateCard(title: "Election unavailable", detail: "The generated machine could not start.", error: error)
                    .frame(maxWidth: .infinity, minHeight: 430)
            }
            DuckDuckLeaderControls(
                isPlaying: isPlaying,
                shuffle: shuffleSchedule,
                reset: { reset() },
                togglePlayback: togglePlayback
            )
        }
        .task { reset() }
    }

    private func shuffleSchedule() {
        deliveryOrder.shuffle()
        lastMove = "The scheduler shuffled its next delivery choices."
    }

    private func reset(message: String = "Press Play to begin the election.") {
        simulationID = UUID()
        isPlaying = false
        isDelivering = false
        deliveryOrder = ring
        delivery = nil
        lastMove = message
        do {
            machine = try ChangRoberts.makeMachine()
            error = nil
        } catch let failure {
            machine = nil
            error = failure.localizedDescription
        }
    }

    private func togglePlayback() {
        if isPlaying {
            isPlaying = false
            return
        }

        isPlaying = true
        let runID = simulationID
        Task { @MainActor in
            while isPlaying && machine?.state.leader == 0 && runID == simulationID {
                let delivered = await deliverNext(runID: runID)
                if !delivered { break }
            }
            if runID == simulationID, let leader = machine?.state.leader, leader != 0 {
                lastMove = "ID \(leader) completed the ring and is the leader."
            }
            if runID == simulationID { isPlaying = false }
        }
    }

    @MainActor
    private func deliverNext(runID: UUID) async -> Bool {
        guard !isDelivering,
              runID == simulationID,
              let machine,
              let node = deliveryOrder.first(where: { node in
                  machine.state.messages.elements.contains { $0[ChangRoberts.MessageSchema.to] == node }
              }),
              let message = machine.state.messages.elements.first(where: { $0[ChangRoberts.MessageSchema.to] == node })
        else { return false }

        isDelivering = true
        defer { isDelivering = false }
        do {
            var nextMachine = machine
            let result = try nextMachine.send(.deliver(process: node))
            guard runID == simulationID else { return false }
            let forwarded = result.after.messages.elements.first {
                $0[ChangRoberts.MessageSchema.candidate] == message[ChangRoberts.MessageSchema.candidate] &&
                    $0[ChangRoberts.MessageSchema.from] == node
            }
            let animation = DuckDelivery(
                candidate: message[ChangRoberts.MessageSchema.candidate],
                from: node,
                to: forwarded?[ChangRoberts.MessageSchema.to]
            )

            delivery = animation
            lastMove = moveDescription(for: animation)
            error = nil
            do {
                try await Task.sleep(for: .milliseconds(50))
            } catch {
                return false
            }
            withAnimation(.easeInOut(duration: 0.8)) {
                delivery?.progress = 1
            }
            do {
                try await Task.sleep(for: .milliseconds(850))
            } catch {
                return false
            }
            guard runID == simulationID else { return false }
            self.machine = nextMachine
            delivery = nil
            return true
        } catch let failure {
            error = failure.localizedDescription
            return false
        }
    }

    private func moveDescription(for delivery: DuckDelivery) -> String {
        if let destination = delivery.to {
            return "Duck ID \(delivery.candidate) runs from Seat \(displayIndex(for: delivery.from)) to Seat \(displayIndex(for: destination))."
        }
        return "Seat \(displayIndex(for: delivery.from)) retires Duck ID \(delivery.candidate)."
    }

    private func displayIndex(for node: ChangRoberts.Node) -> Int {
        ring.firstIndex(of: node).map { $0 + 1 } ?? 0
    }

    private var messageStatus: String {
        guard let state = machine?.state else { return "No formal tokens are available." }
        if state.leader != 0, !state.messages.elements.isEmpty {
            return "\(state.messages.elements.count) older tokens remain in flight; the formal election is complete."
        }
        return "\(state.messages.elements.count) formal tokens remain in flight."
    }

}

private struct ElevatorBankView: View {
    @State private var machine: ElevatorBank?
    @State private var error: String?

    var body: some View {
        DemoScreen(
            title: "Elevator Bank",
            subtitle: "Two riders, two cars, and doors that make every handoff explicit."
        ) {
            if let machine {
                ElevatorBankScene(state: machine.state, riderSummary: riderSummary(machine.state), error: error)
                ElevatorBankControls(
                    operateCarA: { operate(.operate(process: .carA)) },
                    operateCarB: { operate(.operate(process: .carB)) },
                    enabledActions: availableActions,
                    reset: reset
                )
            } else {
                StateCard(title: "Machine unavailable", detail: "The generated machine could not start.", error: error)
                    .frame(maxWidth: .infinity, minHeight: 430)
            }
        }
        .task { reset() }
    }

    private func reset() {
        do {
            let machine = try ElevatorBank.makeMachine()
            self.machine = machine
            error = nil
        } catch let failure {
            machine = nil
            error = failure.localizedDescription
        }
    }

    private func riderSummary(_ state: ElevatorBank.State) -> String {
        let riders = ElevatorBank.Rider.finiteValues.filter { $0 != .none }
        return riders.map { rider in
            let passenger = state.riders[rider]
            return "\(rider.rawValue.capitalized): \(passenger[ElevatorBank.RiderSchema.phase].rawValue), floor \(passenger[ElevatorBank.RiderSchema.floor].rawValue) → \(passenger[ElevatorBank.RiderSchema.destination].rawValue)"
        }.joined(separator: "\n")
    }

    private func operate(_ action: ElevatorBank.Action) {
        guard var machine else { return }
        do {
            _ = try machine.send(action)
            self.machine = machine
            error = nil
        }
        catch let failure { error = failure.localizedDescription }
    }

    private var availableActions: Set<ElevatorBank.Action> {
        guard let machine else { return [] }
        return (try? Set(machine.enabledActions())) ?? []
    }
}

private struct TwoBucketsScene: View {
    let state: TwoBuckets.State
    let error: String?

    var body: some View {
        HStack(alignment: .center, spacing: 72) {
            HStack(alignment: .bottom, spacing: 40) {
                Bucket(capacity: 3, amount: state.three, label: "Bucket 3")
                Bucket(capacity: 5, amount: state.five, label: "Bucket 5", target: 4)
            }
            StateCard(
                title: state.five == 4 ? "Solved" : "Generated machine",
                detail: state.five == 4 ? "Exactly 4 gallons." : "Each enabled button is a formal transition.",
                error: error
            )
        }
        .frame(maxWidth: .infinity, minHeight: 360)
    }
}

private struct TwoBucketsControls: View {
    let fillThree: () -> Void
    let emptyThree: () -> Void
    let pourThreeIntoFive: () -> Void
    let pourFiveIntoThree: () -> Void
    let fillFive: () -> Void
    let emptyFive: () -> Void
    let enabledActions: Set<TwoBuckets.Action>
    let reset: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            actionButton("Fill 3", action: .fillThree, perform: fillThree)
            actionButton("Empty 3", action: .emptyThree, perform: emptyThree)
            actionButton("Pour 3 → 5", tint: .orange, action: .pourThreeIntoFive, perform: pourThreeIntoFive)
            actionButton("Pour 5 → 3", tint: .orange, action: .pourFiveIntoThree, perform: pourFiveIntoThree)
            actionButton("Fill 5", action: .fillFive, perform: fillFive)
            actionButton("Empty 5", action: .emptyFive, perform: emptyFive)
            Spacer()
            Button("Reset", systemImage: "arrow.counterclockwise", action: reset)
        }
    }

    private func actionButton(_ title: String, tint: Color? = nil, action: TwoBuckets.Action, perform: @escaping () -> Void) -> some View {
        Button(title, action: perform)
            .buttonStyle(.borderedProminent)
            .tint(tint)
            .disabled(enabledActions.contains(action) == false)
    }
}

private struct DuckDuckLeaderScene: View {
    let nodes: [ChangRoberts.Node]
    let state: ChangRoberts.State
    let delivery: DuckDelivery?
    let lastMove: String
    let messageStatus: String
    let error: String?

    var body: some View {
        HStack(spacing: 50) {
            RingView(
                nodes: nodes,
                identifiers: state.identifiers,
                messages: state.messages.elements,
                leader: state.leader,
                delivery: delivery
            )
            .frame(width: 520, height: 520)
            StateCard(
                title: state.leader == 0 ? "Election running" : "Leader: \(state.leader)",
                detail: "\(lastMove)\n\n\(messageStatus)",
                error: error
            )
            .frame(width: 260)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct DuckDuckLeaderControls: View {
    let isPlaying: Bool
    let shuffle: () -> Void
    let reset: () -> Void
    let togglePlayback: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button("Shuffle", systemImage: "shuffle", action: shuffle)
            Button("Reset", systemImage: "arrow.counterclockwise", action: reset)
            Button(isPlaying ? "Pause" : "Play", systemImage: isPlaying ? "pause.fill" : "play.fill", action: togglePlayback)
                .buttonStyle(.borderedProminent)
        }
    }
}

private struct ElevatorBankScene: View {
    let state: ElevatorBank.State
    let riderSummary: String
    let error: String?

    var body: some View {
        HStack(alignment: .bottom, spacing: 34) {
            ElevatorFloorBoard(state: state)
            ElevatorShaft(car: .carA, state: state)
            ElevatorShaft(car: .carB, state: state)
            StateCard(title: "Riders", detail: riderSummary, error: error)
                .frame(width: 300)
        }
        .frame(maxWidth: .infinity, minHeight: 430, alignment: .center)
    }
}

private struct ElevatorBankControls: View {
    let operateCarA: () -> Void
    let operateCarB: () -> Void
    let enabledActions: Set<ElevatorBank.Action>
    let reset: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button("Operate Car 1", action: operateCarA)
                .buttonStyle(.borderedProminent)
                .disabled(enabledActions.contains(.operate(process: .carA)) == false)
            Button("Operate Car 2", action: operateCarB)
                .buttonStyle(.borderedProminent)
                .disabled(enabledActions.contains(.operate(process: .carB)) == false)
            Divider().frame(height: 26)
            Button("Reset", systemImage: "arrow.counterclockwise", action: reset)
        }
    }
}

private struct GeneratedSurfaceView: View {
    @State private var results: [GeneratedDemoTestTarget: [GeneratedDemoTestResult]] = [:]
    @State private var running: GeneratedDemoTestTarget?

    var body: some View {
        DemoScreen(
            title: "Generated Tests",
            subtitle: "Run the same generated checks exercised by this consumer package's test target."
        ) {
            ScrollView {
                VStack(spacing: 16) {
                    GeneratedSurfaceSummary()
                    ForEach(GeneratedDemoTestTarget.allCases) { target in
                        GeneratedTestCard(
                            target: target,
                            results: results[target] ?? [],
                            isRunning: running == target,
                            run: { run(target) }
                        )
                    }
                }
                .frame(maxWidth: 720)
            }
        }
    }

    private func run(_ target: GeneratedDemoTestTarget) {
        guard running == nil else { return }
        running = target
        Task { @MainActor in
            let output = await Task.detached(priority: .userInitiated) {
                GeneratedDemoTestSuite.run(target)
            }.value
            results[target] = output
            running = nil
        }
    }
}

private struct GeneratedSurfaceSummary: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What the demonstrations consume")
                .font(.headline)
            HStack(alignment: .top, spacing: 18) {
                GeneratedSurfaceItem(
                    title: "Typed machine",
                    detail: "Each model exposes State, Action, and Transition."
                )
                GeneratedSurfaceItem(
                    title: "Native adapters",
                    detail: "Scenes hold generated values. Actors provide serialized access when needed."
                )
                GeneratedSurfaceItem(
                    title: "Verification suite",
                    detail: "Small models run full generated verification. The ring runs fast generated-surface checks; its full graph belongs in the release pipeline."
                )
            }
        }
        .padding(18)
        .background(.white.opacity(0.08), in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.14)))
    }
}

private struct GeneratedSurfaceItem: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct GeneratedTestCard: View {
    let target: GeneratedDemoTestTarget
    let results: [GeneratedDemoTestResult]
    let isRunning: Bool
    let run: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(target.title).font(.headline)
                    Text("Generated checks, exercised here and by the downstream test target.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(isRunning ? "Running" : "Run", systemImage: isRunning ? "hourglass" : "checkmark.circle") {
                    run()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRunning)
            }

            if results.isEmpty {
                Text("Run the generated suite for this finite model.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(results) { result in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: result.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(result.passed ? .green : .red)
                        Text(result.check).font(.subheadline.weight(.medium))
                        Spacer()
                        Text(result.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(18)
        .background(.white.opacity(0.08), in: .rect(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.14)))
    }
}

private struct DemoScreen<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 26) {
            VStack(spacing: 8) {
                Text(title).font(.system(size: 42, weight: .bold, design: .rounded))
                Text(subtitle).font(.title3).foregroundStyle(.secondary)
            }
            content
        }
        .padding(34)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct Bucket: View {
    let capacity: Int
    let amount: Int
    let label: String
    var target: Int?

    var body: some View {
        VStack(spacing: 12) {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 20)
                    .stroke(.white.opacity(0.35), lineWidth: 3)
                    .frame(width: 145, height: CGFloat(capacity) * 52)
                RoundedRectangle(cornerRadius: 15)
                    .fill(.blue.gradient)
                    .frame(width: 137, height: CGFloat(capacity) * 52 * CGFloat(amount) / CGFloat(capacity))
                Text("\(amount)").font(.system(size: 40, weight: .bold, design: .rounded))
                if let target {
                    Rectangle().fill(.orange).frame(width: 165, height: 2)
                        .offset(y: -CGFloat(target) * 52)
                }
            }
            Text(label).font(.headline)
        }
    }
}

private struct ElevatorFloorBoard: View {
    let state: ElevatorBank.State

    private let floors: [ElevatorBank.Floor] = [.three, .two, .one]

    var body: some View {
        VStack(spacing: 8) {
            Text("Floors")
                .font(.headline)
                .frame(height: 26)
            VStack(spacing: 0) {
                ForEach(floors, id: \.self) { floor in
                    HStack(spacing: 8) {
                        Text("Floor \(floor.rawValue)")
                            .font(.subheadline.weight(.medium))
                        Spacer(minLength: 0)
                        VStack(alignment: .trailing, spacing: 3) {
                            ForEach(waitingRiders(at: floor), id: \.self) { rider in
                                RiderChip(rider: rider, destination: state.riders[rider][ElevatorBank.RiderSchema.destination])
                            }
                        }
                    }
                    .frame(width: 150, height: 112)
                    .overlay(alignment: .bottom) { Rectangle().fill(.white.opacity(0.12)).frame(height: 1) }
                }
            }
        }
    }

    private func waitingRiders(at floor: ElevatorBank.Floor) -> [ElevatorBank.Rider] {
        ElevatorBank.Rider.finiteValues.filter { rider in
            rider != .none
                && state.riders[rider][ElevatorBank.RiderSchema.phase] == .waiting
                && state.riders[rider][ElevatorBank.RiderSchema.floor] == floor
        }
    }
}

private struct ElevatorShaft: View {
    let car: ElevatorBank.CarID
    let state: ElevatorBank.State

    private var vehicle: Record<ElevatorBank.CarSchema> { state.cars[car] }
    private let floors: [ElevatorBank.Floor] = [.three, .two, .one]

    var body: some View {
        VStack(spacing: 8) {
            Text(car == .carA ? "Car 1" : "Car 2")
                .font(.headline)
                .frame(height: 26)
            VStack(spacing: 0) {
                ForEach(floors, id: \.self) { floor in
                    ZStack {
                        if vehicle[ElevatorBank.CarSchema.floor] == floor {
                            CarCabin(
                                vehicle: vehicle,
                                destination: state.riders[vehicle[ElevatorBank.CarSchema.rider]][ElevatorBank.RiderSchema.destination]
                            )
                                .transition(.opacity.combined(with: .scale(scale: 0.95)))
                        }
                    }
                    .frame(width: 176, height: 112)
                    .overlay(alignment: .bottom) { Rectangle().fill(.white.opacity(0.12)).frame(height: 1) }
                }
            }
            .background {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(.white.opacity(0.35), lineWidth: 3)
            }
            .animation(.snappy, value: vehicle)
        }
    }
}

private struct CarCabin: View {
    let vehicle: Record<ElevatorBank.CarSchema>
    let destination: ElevatorBank.Floor

    var body: some View {
        VStack(spacing: 5) {
            HStack(spacing: vehicle[ElevatorBank.CarSchema.door] == .open ? 18 : 2) {
                RoundedRectangle(cornerRadius: 4).fill(.indigo).frame(width: 52, height: 45)
                RoundedRectangle(cornerRadius: 4).fill(.indigo).frame(width: 52, height: 45)
            }
            if vehicle[ElevatorBank.CarSchema.rider] != .none {
                RiderChip(
                    rider: vehicle[ElevatorBank.CarSchema.rider],
                    destination: destination
                )
            }
        }
        .padding(8)
        .background(.indigo.opacity(0.2), in: .rect(cornerRadius: 12))
    }

}

private struct RiderChip: View {
    let rider: ElevatorBank.Rider
    let destination: ElevatorBank.Floor

    var body: some View {
        Label("\(rider.rawValue.capitalized) → \(destination.rawValue)", systemImage: "person.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.orange)
    }
}

private struct DuckDelivery: Equatable {
    let candidate: Int
    let from: ChangRoberts.Node
    let to: ChangRoberts.Node?
    var progress: CGFloat = 0
}

private struct RingView: View {
    let nodes: [ChangRoberts.Node]
    let identifiers: Function<ChangRoberts.Node, Int>
    let messages: [Record<ChangRoberts.MessageSchema>]
    let leader: Int
    let delivery: DuckDelivery?

    var body: some View {
        GeometryReader { proxy in
            DuckRingCanvas(
                nodes: nodes,
                identifiers: identifiers,
                messages: messages,
                leader: leader,
                delivery: delivery,
                layout: DuckRingLayout(size: proxy.size, nodes: nodes)
            )
        }
    }
}

private struct DuckRingLayout {
    let center: CGPoint
    let radius: CGFloat
    let nodes: [ChangRoberts.Node]

    init(size: CGSize, nodes: [ChangRoberts.Node]) {
        center = CGPoint(x: size.width / 2, y: size.height / 2)
        radius = min(size.width, size.height) * 0.38
        self.nodes = nodes
    }

    func ringPoint(for node: ChangRoberts.Node) -> CGPoint {
        guard let index = nodes.firstIndex(of: node) else { return center }
        let angle = CGFloat(index) * (2 * .pi / CGFloat(nodes.count)) - .pi / 2
        return CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
    }

    func messagePoint(
        for node: ChangRoberts.Node,
        ordinal: Int,
        total: Int
    ) -> CGPoint {
        let ringPoint = ringPoint(for: node)
        let radialX = ringPoint.x - center.x
        let radialY = ringPoint.y - center.y
        let radialLength = max((radialX * radialX + radialY * radialY).squareRoot(), 1)
        let tangentOffset = (CGFloat(ordinal) - CGFloat(total - 1) / 2) * 54
        return CGPoint(
            x: center.x + radialX * 0.72 - radialY / radialLength * tangentOffset,
            y: center.y + radialY * 0.72 + radialX / radialLength * tangentOffset
        )
    }

    func deliveryPoint(_ delivery: DuckDelivery) -> CGPoint {
        let start = messagePoint(for: delivery.from, ordinal: 0, total: 1)
        let end = delivery.to.map {
            messagePoint(for: $0, ordinal: 0, total: 1)
        } ?? start
        return CGPoint(
            x: start.x + (end.x - start.x) * delivery.progress,
            y: start.y + (end.y - start.y) * delivery.progress
        )
    }

}

private struct DuckRingCanvas: View {
    let nodes: [ChangRoberts.Node]
    let identifiers: Function<ChangRoberts.Node, Int>
    let messages: [Record<ChangRoberts.MessageSchema>]
    let leader: Int
    let delivery: DuckDelivery?
    let layout: DuckRingLayout

    var body: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.25), lineWidth: 4)
                .frame(width: layout.radius * 2, height: layout.radius * 2)
            DuckRingSeats(nodes: nodes, identifiers: identifiers, leader: leader, layout: layout)
            DuckRingMessages(messages: messages, activeDelivery: delivery, layout: layout)
            if let delivery {
                DuckMessageBadge(candidate: delivery.candidate)
                    .scaleEffect(1.1)
                    .opacity(delivery.to == nil ? 1 - delivery.progress : 1)
                    .position(layout.deliveryPoint(delivery))
            }
            DuckRingStatus(messageCount: messages.count)
        }
    }
}

private struct DuckRingSeats: View {
    let nodes: [ChangRoberts.Node]
    let identifiers: Function<ChangRoberts.Node, Int>
    let leader: Int
    let layout: DuckRingLayout

    var body: some View {
        ForEach(Array(nodes.enumerated()), id: \.offset) { index, node in
            DuckSeat(
                number: index + 1,
                identifier: identifiers[node],
                isLeaderHome: identifiers[node] == leader && leader != 0
            )
            .position(layout.ringPoint(for: node))
        }
    }
}

private struct DuckSeat: View {
    let number: Int
    let identifier: Int
    let isLeaderHome: Bool

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: "chair.fill")
            Text("Seat \(number)").font(.caption.bold())
            Text("home ID \(identifier)").font(.caption2)
        }
        .foregroundStyle(isLeaderHome ? .orange : .indigo)
        .frame(width: 72, height: 64)
        .background(.black.opacity(0.5), in: .circle)
        .overlay(Circle().stroke(isLeaderHome ? .orange : .indigo, lineWidth: isLeaderHome ? 4 : 3))
        .opacity(isLeaderHome ? 1 : 0.75)
    }
}

private struct DuckRingMessages: View {
    let messages: [Record<ChangRoberts.MessageSchema>]
    let activeDelivery: DuckDelivery?
    let layout: DuckRingLayout

    var body: some View {
        ForEach(Array(messages.enumerated()), id: \.offset) { index, message in
            if message[ChangRoberts.MessageSchema.candidate] != activeDelivery?.candidate {
                let destination = message[ChangRoberts.MessageSchema.to]
                let placement = placement(for: destination, at: index)
                DuckMessageBadge(candidate: message[ChangRoberts.MessageSchema.candidate])
                    .position(layout.messagePoint(
                        for: destination,
                        ordinal: placement.ordinal,
                        total: placement.total
                    ))
            }
        }
    }

    private func placement(for destination: ChangRoberts.Node, at index: Int) -> (ordinal: Int, total: Int) {
        let prior = messages[..<index].filter { $0[ChangRoberts.MessageSchema.to] == destination }.count
        let total = messages.filter { $0[ChangRoberts.MessageSchema.to] == destination }.count
        return (prior, total)
    }
}

private struct DuckRingStatus: View {
    let messageCount: Int

    var body: some View {
        VStack(spacing: 4) {
            Text("\(messageCount) ducks in flight")
            Text("Seats stay put. Duck IDs travel clockwise.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .font(.headline)
        .foregroundStyle(.orange)
    }
}

private struct DuckMessageBadge: View {
    let candidate: Int

    var body: some View {
        Label("Duck ID \(candidate)", systemImage: "bird.fill")
            .font(.caption.bold())
            .foregroundStyle(.black)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(.orange.gradient, in: .capsule)
    }
}

private struct StateCard: View {
    let title: String
    let detail: String
    let error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.headline)
            Text(detail).foregroundStyle(.secondary)
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(.white.opacity(0.08), in: .rect(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.16)))
    }
}
