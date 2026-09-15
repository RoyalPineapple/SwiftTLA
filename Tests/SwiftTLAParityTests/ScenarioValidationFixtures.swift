import SwiftTLA
import SwiftTLAMacros
import UpstreamParity

@TLAModel
struct DeadlockScenarios {
    enum Step: String, CaseIterable { case wait }

    static var spec: TLASpec {
        #spec("DeadlockScenarios") { scope in
            let value = scope.sharedVar("value", initial: 0)
            Algorithm("Blocked") {
                Do(Step.wait, when: value < 0) { Goto(Step.wait) }
            }
            Validation("Unexpected deadlock") {}
            Validation("Expected deadlock") {}.expectDeadlock(.violated)
        }
    }
}

struct IncompleteCounterScenario: ModelValidationScenario {
    typealias Machine = ConfiguredCounter
    typealias Property = ConfiguredCounter.Property
    let original: ConfiguredCounter.ValidationScenario
    var name: String { original.name }
    var expectations: [Property: ValidationExpectation] { [:] }
    var deadlockExpectation: ValidationExpectation? { original.deadlockExpectation }
    func initialMachines() throws -> [Machine] { try original.initialMachines() }
    func render() throws -> RenderedSpecification { try original.render() }
    var formalPropertyNames: [Property: String] { original.formalPropertyNames }
}
