import SwiftTLA

/// The generated-machine checks used by the demonstrations and their test target.
public struct GeneratedDemoCheck: Identifiable, Sendable {
    public let target: String
    public let check: String
    public let detail: String
    public let passed: Bool

    public var id: String { "\(target).\(check)" }
}

public enum GeneratedDemoTestTarget: String, CaseIterable, Identifiable, Sendable {
    case twoBuckets
    case duckDuckLeader
    case elevatorBank

    public var id: Self { self }

    public var title: String {
        switch self {
        case .twoBuckets: "Two Buckets"
        case .duckDuckLeader: "Duck, Duck, Leader"
        case .elevatorBank: "Elevator Bank"
        }
    }
}

public enum GeneratedDemoTestSuite {
    public static func run(_ target: GeneratedDemoTestTarget) -> [GeneratedDemoCheck] {
        switch target {
        case .twoBuckets:
            machineChecks(for: target.title, makeMachine: TwoBuckets.makeMachine)
        case .duckDuckLeader:
            ringChecks()
        case .elevatorBank:
            machineChecks(for: target.title, makeMachine: ElevatorBank.makeMachine)
        }
    }

    public static func runAll() -> [GeneratedDemoCheck] {
        GeneratedDemoTestTarget.allCases.flatMap(run)
    }

    private static func machineChecks<Machine>(
        for target: String,
        makeMachine: () throws -> Machine
    ) -> [GeneratedDemoCheck] {
        [
            check(target: target, name: "Typed machine") { _ = try makeMachine() }
        ]
    }

    /// The twelve-node ring has a deliberately large asynchronous state space.
    /// The release pipeline exhaustively checks it; the app runs these immediate,
    /// generated-surface checks so its button remains responsive.
    private static func ringChecks() -> [GeneratedDemoCheck] {
        [
            check(target: GeneratedDemoTestTarget.duckDuckLeader.title, name: "Formal surface", action: { () throws -> Void in
                let description = try ChangRoberts.spec.compile().description
                guard description.variables.isEmpty == false, description.actions.isEmpty == false else {
                    throw GeneratedDemoSuiteError.unexpectedFormalSurface
                }
            }),
            check(target: GeneratedDemoTestTarget.duckDuckLeader.title, name: "Generated state", action: { () throws -> Void in
                let machine = try ChangRoberts.makeMachine()
                guard machine.state.leader == 0, machine.state.messages.elements.count == 12 else {
                    throw GeneratedDemoSuiteError.unexpectedInitialState
                }
            }),
            check(target: GeneratedDemoTestTarget.duckDuckLeader.title, name: "Typed delivery", action: { () throws -> Void in
                var machine = try ChangRoberts.makeMachine()
                _ = try machine.send(.deliver(process: .six))
                guard machine.state.messages.elements.contains(where: {
                    $0.value(for: ChangRoberts.MessageSchema.candidate) == 12 &&
                    $0.value(for: ChangRoberts.MessageSchema.from) == .six &&
                    $0.value(for: ChangRoberts.MessageSchema.to) == .seven
                }) else {
                    throw GeneratedDemoSuiteError.deliveryWasNotForwarded
                }
            }),
            check(target: GeneratedDemoTestTarget.duckDuckLeader.title, name: "Enabled actions", action: { () throws -> Void in
                let machine = try ChangRoberts.makeMachine()
                guard try machine.isEnabled(.deliver(process: .six)) else {
                    throw GeneratedDemoSuiteError.expectedActionUnavailable
                }
            })
        ]
    }

    private static func check(
        target: String,
        name: String,
        action: () throws -> Void
    ) -> GeneratedDemoCheck {
        do {
            try action()
            return .init(target: target, check: name, detail: "Passed", passed: true)
        } catch {
            return .init(target: target, check: name, detail: String(describing: error), passed: false)
        }
    }

    private static func check(
        target: String,
        name: String,
        action: () throws -> String
    ) -> GeneratedDemoCheck {
        do {
            return .init(target: target, check: name, detail: try action(), passed: true)
        } catch {
            return .init(target: target, check: name, detail: String(describing: error), passed: false)
        }
    }
}

private enum GeneratedDemoSuiteError: Error {
    case unexpectedFormalSurface
    case unexpectedInitialState
    case deliveryWasNotForwarded
    case expectedActionUnavailable
}
