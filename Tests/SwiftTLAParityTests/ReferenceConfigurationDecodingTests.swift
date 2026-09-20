import Foundation
import Testing
@testable import UpstreamParity

struct ReferenceConfigurationDecodingTests {
  @Test("decisive reference coverage rejects missing, extra, duplicate, and disabled checks", arguments: [
    #"{"declarations":"","invariants":[],"properties":[],"checksDeadlock":true}"#,
    #"{"declarations":"","invariants":["BelowThree","Other"],"properties":[],"checksDeadlock":true}"#,
    #"{"declarations":"","invariants":["BelowThree","BelowThree"],"properties":[],"checksDeadlock":true}"#,
    #"{"declarations":"","invariants":["BelowThree"],"properties":[],"checksDeadlock":false}"#
  ])
  func rejectsChangedDecisiveSelection(input: String) throws {
    let scenario = try #require(TraceReplayCounter.validationScenarios().first)
    let configuration = try JSONDecoder().decode(TLCReferenceConfiguration.self, from: Data(input.utf8))
    #expect(throws: TLCPropertyCheckError.self) {
      try configuration.validateDecisiveCoverage(scenario.render())
    }
  }
  @Test("reference configuration decoding preserves every declared check")
  func preservesCheckDeclarations() throws {
    let input = Data(#"{"declarations":"SPECIFICATION Spec\n","invariants":["Safe"],"properties":["Live"],"checksDeadlock":true}"#.utf8)
    let configuration = try JSONDecoder().decode(TLCReferenceConfiguration.self, from: input)
    #expect(configuration.declarations == "SPECIFICATION Spec\n")
    #expect(configuration.invariants == ["Safe"])
    #expect(configuration.properties == ["Live"])
    #expect(configuration.checksDeadlock)
  }

  @Test("reference configuration decoding rejects fields it cannot preserve")
  func rejectsUnknownFields() {
    let input = Data(#"{"declarations":"SPECIFICATION Spec\n","invariants":[],"properties":[],"checksDeadlock":false,"extraChecks":["MustHold"]}"#.utf8)
    #expect(throws: DecodingError.self) {
      try JSONDecoder().decode(TLCReferenceConfiguration.self, from: input)
    }
  }

  @Test("reference configuration decoding requires typed check selection", arguments: [
    #"{"declarations":"SPECIFICATION Spec\n","invariants":[],"properties":[]}"#,
    #"{"declarations":"SPECIFICATION Spec\n","invariants":[],"properties":[],"checksDeadlock":"false"}"#,
    #"{"declarations":"SPECIFICATION Spec\n","invariants":[1],"properties":[],"checksDeadlock":false}"#,
  ])
  func rejectsMalformedCheckSelection(input: String) {
    #expect(throws: DecodingError.self) {
      try JSONDecoder().decode(TLCReferenceConfiguration.self, from: Data(input.utf8))
    }
  }
}
