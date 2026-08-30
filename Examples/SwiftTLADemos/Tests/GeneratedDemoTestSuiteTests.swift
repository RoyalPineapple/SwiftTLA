import Testing
@testable import SwiftTLADemos

struct GeneratedDemoTestSuiteTests {
    @Test("consumer test suite runs every generated-machine check")
    func generatedChecksPass() {
        for target in GeneratedDemoTestTarget.allCases {
            let expectedCount = switch target {
            case .twoBuckets, .elevatorBank: 1
            case .duckDuckLeader: 4
            }
            let checks = GeneratedDemoTestSuite.run(target)
            #expect(checks.count == expectedCount)
            let allPassed = checks.allSatisfy { $0.passed }
            #expect(allPassed)
        }
    }
}
