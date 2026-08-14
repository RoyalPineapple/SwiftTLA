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
            testResults(for: target.title, verifySpec: TwoBuckets.verifySpec, matrix: TwoBuckets.transitionMatrix,
                        verifyTransitions: TwoBuckets.verifyTransitions, verifyInvariants: TwoBuckets.verifyInvariants)
        case .duckDuckLeader:
            testResults(for: target.title, verifySpec: ChangRoberts.verifySpec, matrix: ChangRoberts.transitionMatrix,
                        verifyTransitions: ChangRoberts.verifyTransitions, verifyInvariants: ChangRoberts.verifyInvariants)
        case .elevatorBank:
            testResults(for: target.title, verifySpec: ElevatorBank.verifySpec, matrix: ElevatorBank.transitionMatrix,
                        verifyTransitions: ElevatorBank.verifyTransitions, verifyInvariants: ElevatorBank.verifyInvariants)
        }
    }

    public static func runAll() -> [GeneratedDemoTestResult] {
        GeneratedDemoTestTarget.allCases.flatMap(run)
    }

    private static func testResults<State>(
        for model: String,
        verifySpec: () throws -> Void,
        matrix: () throws -> [(from: State, invocation: TLAActionInvocation, to: State)],
        verifyTransitions: () throws -> Void,
        verifyInvariants: () throws -> Void
    ) -> [GeneratedDemoTestResult] {
        [
            result(model: model, check: "Specification", action: verifySpec),
            result(model: model, check: "Reachable graph") {
                let count = try matrix().count
                guard count > 0 else { throw GeneratedDemoSuiteError.emptyMatrix }
                return "\(count) generated transitions"
            },
            result(model: model, check: "Native transitions", action: verifyTransitions),
            result(model: model, check: "Invariants", action: verifyInvariants)
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
    case emptyMatrix
}
