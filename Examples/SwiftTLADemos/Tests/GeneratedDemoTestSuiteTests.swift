import Testing
@testable import SwiftTLADemos

struct GeneratedDemoTestSuiteTests {
    @Test("consumer test suite runs every generated-machine check")
    func generatedChecksPass() {
        for target in GeneratedDemoTestTarget.allCases {
            let checks = GeneratedDemoTestSuite.run(target)
            #expect(checks.isEmpty == false)
            let allPassed = checks.allSatisfy { $0.passed }
            #expect(allPassed)
        }
    }
}
