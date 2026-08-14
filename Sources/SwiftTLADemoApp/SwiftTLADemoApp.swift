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
        }
        .padding(24)
        .background(Color.black.opacity(0.9))
    }
}

private struct TwoBucketsView: View {
    @State private var machine = TwoBuckets.Observable()
    @State private var error: String?

    private var state: TwoBuckets.State { machine.state }

    var body: some View {
        DemoScreen(title: "Two Buckets", subtitle: "Measure exactly 4 gallons.") {
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

            HStack(spacing: 10) {
                bucketButton("Fill 3") { _ = try await machine._fillThree() }
                bucketButton("Empty 3") { _ = try await machine._emptyThree() }
                bucketButton("Pour 3 → 5") { _ = try await machine._pourThreeIntoFive() }
                    .tint(.orange)
                bucketButton("Pour 5 → 3") { _ = try await machine._pourFiveIntoThree() }
                    .tint(.orange)
                bucketButton("Fill 5") { _ = try await machine._fillFive() }
                bucketButton("Empty 5") { _ = try await machine._emptyFive() }
                Spacer()
                Button("Reset", systemImage: "arrow.counterclockwise") {
                    machine = TwoBuckets.Observable()
                    error = nil
                }
            }
        }
    }

    private func bucketButton(_ title: String, action: @escaping () async throws -> Void) -> some View {
        Button(title) { perform(action) }
            .buttonStyle(.borderedProminent)
    }

    private func perform(_ action: @escaping () async throws -> Void) {
        Task { @MainActor in
            do { try await action(); error = nil }
            catch let failure { error = failure.localizedDescription }
        }
    }
}

private struct DuckDuckLeaderView: View {
    @State private var actor = ChangRoberts.Actor()
    @State private var state = ChangRoberts().state
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
            HStack(spacing: 50) {
                RingView(
                    nodes: ring,
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

            HStack(spacing: 12) {
                Button("Shuffle", systemImage: "shuffle") { shuffleSchedule() }
                Button("Reset", systemImage: "arrow.counterclockwise") { reset() }
                Button(isPlaying ? "Pause" : "Play", systemImage: isPlaying ? "pause.fill" : "play.fill") {
                    togglePlayback()
                }
                .buttonStyle(.borderedProminent)
            }
        }
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
        actor = ChangRoberts.Actor()
        state = ChangRoberts().state
        delivery = nil
        lastMove = message
        error = nil
    }

    private func togglePlayback() {
        if isPlaying {
            isPlaying = false
            return
        }

        isPlaying = true
        let runID = simulationID
        Task { @MainActor in
            while isPlaying && state.leader == 0 && runID == simulationID {
                let delivered = await deliverNext(runID: runID)
                if !delivered { break }
            }
            if runID == simulationID, state.leader != 0 {
                lastMove = "ID \(state.leader) completed the ring and is the leader."
            }
            if runID == simulationID { isPlaying = false }
        }
    }

    @MainActor
    private func deliverNext(runID: UUID) async -> Bool {
        guard !isDelivering,
              runID == simulationID,
              let node = deliveryOrder.first(where: { node in
                  state.messages.elements.contains { $0[ChangRoberts.MessageSchema.to] == node }
              }),
              let message = state.messages.elements.first(where: { $0[ChangRoberts.MessageSchema.to] == node })
        else { return false }

        isDelivering = true
        defer { isDelivering = false }
        do {
            let runningActor = actor
            let result = try await runningActor.execute(
                ChangRoberts.Actor.ActionLabel.deliver(process: node).toInvocation()
            )
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
            try? await Task.sleep(for: .milliseconds(50))
            withAnimation(.easeInOut(duration: 0.8)) {
                delivery?.progress = 1
            }
            try? await Task.sleep(for: .milliseconds(850))
            guard runID == simulationID else { return false }
            state = result.after
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
        if state.leader != 0, !state.messages.elements.isEmpty {
            return "\(state.messages.elements.count) older tokens remain in flight; the formal election is complete."
        }
        return "\(state.messages.elements.count) formal tokens remain in flight."
    }

}

private struct ElevatorBankView: View {
    @State private var machine = ElevatorBank.Observable()
    @State private var error: String?

    private var state: ElevatorBank.State { machine.state }

    var body: some View {
        DemoScreen(
            title: "Elevator Bank",
            subtitle: "Two riders, two cars, and doors that make every handoff explicit."
        ) {
            HStack(alignment: .center, spacing: 60) {
                ElevatorShaft(car: .carA, state: state)
                ElevatorShaft(car: .carB, state: state)
                StateCard(
                    title: "Formal state",
                    detail: riderSummary,
                    error: error
                )
                .frame(width: 265)
            }
            .frame(maxWidth: .infinity, minHeight: 430)

            HStack(spacing: 12) {
                Button("Advance Car 1") { operate(.carA) }
                    .buttonStyle(.borderedProminent)
                Button("Advance Car 2") { operate(.carB) }
                    .buttonStyle(.borderedProminent)
                Spacer()
                Button("Reset", systemImage: "arrow.counterclockwise") {
                    machine = ElevatorBank.Observable()
                    error = nil
                }
            }
        }
    }

    private var riderSummary: String {
        let riders = ElevatorBank.Rider.formalDomain.filter { $0 != .none }
        return riders.map { rider in
            "\(rider.rawValue.capitalized): \(state.riders[rider][ElevatorBank.RiderSchema.phase].rawValue)"
        }.joined(separator: "\n")
    }

    private func operate(_ car: ElevatorBank.CarID) {
        Task { @MainActor in
            do { _ = try await machine._operate(process: car); error = nil }
            catch let failure { error = failure.localizedDescription }
        }
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

private struct ElevatorShaft: View {
    let car: ElevatorBank.CarID
    let state: ElevatorBank.State

    private var vehicle: Record<ElevatorBank.CarSchema> { state.cars[car] }

    var body: some View {
        VStack(spacing: 8) {
            Text(car == .carA ? "Car 1" : "Car 2").font(.headline)
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(.white.opacity(0.35), lineWidth: 3)
                    .frame(width: 165, height: 360)
                ForEach(ElevatorBank.Floor.formalDomain, id: \.self) { floor in
                    Rectangle().fill(.white.opacity(0.12)).frame(height: 1)
                        .offset(y: floorOffset(floor))
                }
                if vehicle[ElevatorBank.CarSchema.floor] == .one || vehicle[ElevatorBank.CarSchema.floor] == .two || vehicle[ElevatorBank.CarSchema.floor] == .three {
                    CarCabin(vehicle: vehicle)
                        .offset(y: floorOffset(vehicle[ElevatorBank.CarSchema.floor]))
                        .animation(.snappy, value: vehicle)
                }
            }
        }
    }

    private func floorOffset(_ floor: ElevatorBank.Floor) -> CGFloat {
        switch floor {
        case .one: 112
        case .two: 0
        case .three: -112
        }
    }
}

private struct CarCabin: View {
    let vehicle: Record<ElevatorBank.CarSchema>

    var body: some View {
        VStack(spacing: 5) {
            HStack(spacing: vehicle[ElevatorBank.CarSchema.door] == .open ? 18 : 2) {
                RoundedRectangle(cornerRadius: 4).fill(.indigo).frame(width: 52, height: 45)
                RoundedRectangle(cornerRadius: 4).fill(.indigo).frame(width: 52, height: 45)
            }
            if vehicle[ElevatorBank.CarSchema.rider] != .none {
                Text("♟ → \(vehicle[ElevatorBank.CarSchema.rider].rawValue.capitalized)")
                    .font(.caption.bold()).foregroundStyle(.orange)
            }
        }
        .padding(8)
        .background(.indigo.opacity(0.2), in: .rect(cornerRadius: 12))
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
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let radius = min(proxy.size.width, proxy.size.height) * 0.38
            ZStack {
                Circle().stroke(.white.opacity(0.25), lineWidth: 4)
                    .frame(width: radius * 2, height: radius * 2)
                ForEach(Array(nodes.enumerated()), id: \.offset) { index, node in
                    let point = ringPoint(for: node, center: center, radius: radius)
                    let isLeaderHome = identifiers[node] == leader && leader != 0
                    VStack(spacing: 2) {
                        Image(systemName: "chair.fill")
                        Text("Seat \(index + 1)").font(.caption.bold())
                        Text("home ID \(identifiers[node])").font(.caption2)
                    }
                    .foregroundStyle(isLeaderHome ? .orange : .indigo)
                    .frame(width: 72, height: 64)
                    .background(.black.opacity(0.5), in: .circle)
                    .overlay(Circle().stroke(isLeaderHome ? .orange : .indigo, lineWidth: isLeaderHome ? 4 : 3))
                    .opacity(isLeaderHome ? 1 : 0.75)
                    .position(point)
                }
                ForEach(Array(messages.enumerated()), id: \.offset) { index, message in
                    let destination = message[ChangRoberts.MessageSchema.to]
                    if delivery?.candidate != message[ChangRoberts.MessageSchema.candidate] {
                        let priorAtDestination = messages[..<index].filter {
                            $0[ChangRoberts.MessageSchema.to] == destination
                        }.count
                        let totalAtDestination = messages.filter {
                            $0[ChangRoberts.MessageSchema.to] == destination
                        }.count
                        messageBadge(candidate: message[ChangRoberts.MessageSchema.candidate])
                            .position(messagePoint(
                                for: destination,
                                center: center,
                                radius: radius,
                                ordinal: priorAtDestination,
                                total: totalAtDestination
                            ))
                    }
                }
                if let delivery {
                    messageBadge(candidate: delivery.candidate)
                        .scaleEffect(1.1)
                        .opacity(delivery.to == nil ? 1 - delivery.progress : 1)
                        .position(deliveryPoint(delivery, center: center, radius: radius))
                }
                VStack(spacing: 4) {
                    Text("\(messages.count) ducks in flight")
                    Text("Seats stay put. Duck IDs travel clockwise.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .font(.headline)
                .foregroundStyle(.orange)
            }
        }
    }

    private func ringPoint(for node: ChangRoberts.Node, center: CGPoint, radius: CGFloat) -> CGPoint {
        guard let index = nodes.firstIndex(of: node) else { return center }
        let angle = CGFloat(index) * (2 * .pi / CGFloat(nodes.count)) - .pi / 2
        return CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
    }

    private func messagePoint(
        for node: ChangRoberts.Node,
        center: CGPoint,
        radius: CGFloat,
        ordinal: Int,
        total: Int
    ) -> CGPoint {
        let ringPoint = ringPoint(for: node, center: center, radius: radius)
        let radialX = ringPoint.x - center.x
        let radialY = ringPoint.y - center.y
        let radialLength = max((radialX * radialX + radialY * radialY).squareRoot(), 1)
        let tangentOffset = (CGFloat(ordinal) - CGFloat(total - 1) / 2) * 54
        return CGPoint(
            x: center.x + radialX * 0.72 - radialY / radialLength * tangentOffset,
            y: center.y + radialY * 0.72 + radialX / radialLength * tangentOffset
        )
    }

    private func deliveryPoint(_ delivery: DuckDelivery, center: CGPoint, radius: CGFloat) -> CGPoint {
        let start = messagePoint(for: delivery.from, center: center, radius: radius, ordinal: 0, total: 1)
        let end = delivery.to.map {
            messagePoint(for: $0, center: center, radius: radius, ordinal: 0, total: 1)
        } ?? start
        return CGPoint(
            x: start.x + (end.x - start.x) * delivery.progress,
            y: start.y + (end.y - start.y) * delivery.progress
        )
    }

    @ViewBuilder
    private func messageBadge(candidate: Int) -> some View {
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
