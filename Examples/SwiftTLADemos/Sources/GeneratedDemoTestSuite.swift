import SwiftTLA

/// The generated-machine checks used by the demonstrations and their test target.
///
/// Each result comes from generated model APIs. The suite does not recreate the
/// transition relation or invariants in application code.
public struct GeneratedDemoTestResult: Identifiable, Sendable {
    public let model: String
    public let check: String
    public let detail: String
    public let passed: Bool

    public var id: String { "\(model).\(check)" }
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
    public static func run(_ target: GeneratedDemoTestTarget) -> [GeneratedDemoTestResult] {
        switch target {
        case .twoBuckets:
            machineResults(for: target.title, makeMachine: TwoBuckets.makeMachine)
        case .duckDuckLeader:
            ringTestResults()
        case .elevatorBank:
            machineResults(for: target.title, makeMachine: ElevatorBank.makeMachine)
        }
    }

    public static func runAll() -> [GeneratedDemoTestResult] {
        GeneratedDemoTestTarget.allCases.flatMap(run)
    }

    private static func machineResults<Machine>(
        for model: String,
        makeMachine: () throws -> Machine
    ) -> [GeneratedDemoTestResult] {
        [
            result(model: model, check: "Typed machine") { _ = try makeMachine() }
        ]
    }

    /// The twelve-node ring has a deliberately large asynchronous state space.
    /// The release pipeline exhaustively checks it; the app runs these immediate,
    /// generated-surface checks so its button remains responsive.
    private static func ringTestResults() -> [GeneratedDemoTestResult] {
        [
            result(model: GeneratedDemoTestTarget.duckDuckLeader.title, check: "Formal surface", action: { () throws -> Void in
                let spec = ChangRoberts.spec
                guard !spec.variables.isEmpty, !spec.actions.isEmpty else {
                    throw GeneratedDemoSuiteError.unexpectedFormalSurface
                }
            }),
            result(model: GeneratedDemoTestTarget.duckDuckLeader.title, check: "Generated state", action: { () throws -> Void in
                let machine = try ChangRoberts.makeMachine()
                guard machine.state.leader == 0, machine.state.messages.elements.count == 12 else {
                    throw GeneratedDemoSuiteError.unexpectedInitialState
                }
            }),
            result(model: GeneratedDemoTestTarget.duckDuckLeader.title, check: "Typed delivery", action: { () throws -> Void in
                var machine = try ChangRoberts.makeMachine()
                _ = try machine.send(.deliver(process: .six))
                guard machine.state.messages.elements.contains(where: {
                    $0[ChangRoberts.MessageSchema.candidate] == 12 &&
                    $0[ChangRoberts.MessageSchema.from] == .six &&
                    $0[ChangRoberts.MessageSchema.to] == .seven
                }) else {
                    throw GeneratedDemoSuiteError.deliveryWasNotForwarded
                }
            }),
            result(model: GeneratedDemoTestTarget.duckDuckLeader.title, check: "Enabled actions", action: { () throws -> Void in
                let machine = try ChangRoberts.makeMachine()
                guard try machine.isEnabled(.deliver(process: .six)) else {
                    throw GeneratedDemoSuiteError.expectedActionUnavailable
                }
            })
        ]
    }

    private static func result(
        model: String,
        check: String,
        action: () throws -> Void
    ) -> GeneratedDemoTestResult {
        do {
            try action()
            return .init(model: model, check: check, detail: "Passed", passed: true)
        } catch {
            return .init(model: model, check: check, detail: String(describing: error), passed: false)
        }
    }

    private static func result(
        model: String,
        check: String,
        action: () throws -> String
    ) -> GeneratedDemoTestResult {
        do {
            return .init(model: model, check: check, detail: try action(), passed: true)
        } catch {
            return .init(model: model, check: check, detail: String(describing: error), passed: false)
        }
    }
}

private enum GeneratedDemoSuiteError: Error {
    case unexpectedFormalSurface
    case unexpectedInitialState
    case deliveryWasNotForwarded
    case expectedActionUnavailable
}
