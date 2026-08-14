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

    private let ring: [ChangRoberts.Node] = [.one, .two, .three, .four, .five, .six, .seven, .eight, .nine, .ten, .eleven, .twelve]

    var body: some View {
        DemoScreen(
            title: "Duck, Duck, Leader",
            subtitle: "A message carrying the largest identifier completes the ring."
        ) {
            HStack(spacing: 50) {
                RingView(nodes: ring, messages: state.messages.elements, leader: state.leader)
                    .frame(width: 520, height: 520)
                StateCard(
                    title: state.leader == 0 ? "Election running" : "Leader: \(state.leader)",
                    detail: "\(state.messages.elements.count) formal messages remain.",
                    error: error
                )
                .frame(width: 260)
            }
            .frame(maxWidth: .infinity)

            HStack {
                Button("Deliver random message", systemImage: "arrow.clockwise") { deliver() }
                    .buttonStyle(.borderedProminent)
                Button("Reset", systemImage: "arrow.counterclockwise") {
                    actor = ChangRoberts.Actor()
                    state = ChangRoberts().state
                    error = nil
                }
            }
        }
    }

    private func deliver() {
        guard let message = state.messages.elements.first else { return }
        Task {
            do {
                _ = try await actor.execute(
                    ChangRoberts.Actor.ActionLabel.deliver(process: message[ChangRoberts.MessageSchema.to]).toInvocation()
                )
                let updated = await actor.state
                await MainActor.run { state = updated; error = nil }
            } catch let failure {
                await MainActor.run { self.error = failure.localizedDescription }
            }
        }
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

private struct RingView: View {
    let nodes: [ChangRoberts.Node]
    let messages: [Record<ChangRoberts.MessageSchema>]
    let leader: Int

    var body: some View {
        GeometryReader { proxy in
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let radius = min(proxy.size.width, proxy.size.height) * 0.38
            ZStack {
                Circle().stroke(.white.opacity(0.25), lineWidth: 4)
                    .frame(width: radius * 2, height: radius * 2)
                ForEach(Array(nodes.enumerated()), id: \.offset) { index, node in
                    let angle = CGFloat(index) * (2 * .pi / CGFloat(nodes.count)) - .pi / 2
                    let point = CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
                    VStack(spacing: 2) {
                        Image(systemName: "bird.fill")
                        Text("\(index + 1)").font(.caption.bold())
                    }
                    .foregroundStyle(leader == index + 1 ? .orange : .indigo)
                    .frame(width: 54, height: 54)
                    .background(.black.opacity(0.5), in: .circle)
                    .overlay(Circle().stroke(leader == index + 1 ? .orange : .indigo, lineWidth: 3))
                    .position(point)
                }
                Text("\(messages.count) messages")
                    .font(.headline).foregroundStyle(.orange)
            }
        }
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
