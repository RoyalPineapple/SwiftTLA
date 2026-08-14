import Testing
@testable import SwiftTLADemos

struct GeneratedDemoTestSuiteTests {
    @Test("consumer test suite runs every generated-model check")
    func generatedChecksPass() {
        for target in GeneratedDemoTestTarget.allCases {
            let results = GeneratedDemoTestSuite.run(target)
            #expect(results.count == 4)
            let allPassed = results.allSatisfy { $0.passed }
            #expect(allPassed)
        }
    }
}
