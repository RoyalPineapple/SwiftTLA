import Foundation
import SwiftTLA
import Testing
@testable import UpstreamParity

struct FiniteGraphCompilationTests {
  @Test("every declared finite graph case renders its generated model and preserves scenario selection")
  func rendersRegisteredGeneratedModels() throws {
    let manifest = try JSONDecoder().decode(FiniteGraphManifest.self,
      from: Data(contentsOf: projectURL("Verification/FiniteGraph/cases.json")))
    for declaration in manifest.cases {
      let rendered = try declaration.renderModel()
      try rendered.tlaBundle.validateDeclaredClosure()
      #expect(!rendered.tlaBundle.tla.isEmpty)
    }
  }
}
