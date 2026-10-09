import SwiftTLA
import SwiftTLAMacros
import UpstreamParity

@TLAModel
struct DeadlockScenarios {
    enum Step: String, CaseIterable { case wait }

    static var spec: TLASpec {
        #spec("DeadlockScenarios") { scope in
            let value = scope.sharedVar(_name: "value", initial: 0)
            let blocked = Algorithm(label: "Blocked") {
                Do(Step.wait, when: value < 0) { Goto(Step.wait) }
            }
            blocked
            let unexpectedDeadlock = Validation(label: "Unexpected deadlock") {}
            unexpectedDeadlock
            let expectedDeadlock = Validation(label: "Expected deadlock") {}.expectDeadlock(.violated)
            expectedDeadlock
        }
    }
}

struct IncompleteCounterScenario: ModelValidationScenario {
    typealias Machine = ConfiguredCounter
    typealias Property = ConfiguredCounter.Property
    let original: ConfiguredCounter.ValidationScenario
    var name: String { original.name }
    var displayName: String { original.displayName }
    var checking: ModelChecks<Property> { original.checking }
    var behavior: ModelBehavior { original.behavior }
    var expectations: [Property: ValidationExpectation] { [:] }
    var deadlockExpectation: ValidationExpectation? { original.deadlockExpectation }
    func initialMachines() throws -> [Machine] { try original.initialMachines() }
    func render() throws -> RenderedSpecification { try original.render() }
    var formalPropertyNames: [Property: String] { original.formalPropertyNames }
}
