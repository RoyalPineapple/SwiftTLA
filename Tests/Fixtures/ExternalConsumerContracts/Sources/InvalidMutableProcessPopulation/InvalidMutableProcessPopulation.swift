import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct InvalidMutableProcessPopulationModel {
    enum Step: String, CaseIterable { case advance }

    static var spec: TLASpec {
        #spec("InvalidMutableProcessPopulation") { scope in
            let activeDevices = scope.sharedVar(initial: Set<String>(["east", "west"]))
            let algorithm = Algorithm(scoped: { _ in
                Each(activeDevices) { _ in
                    Do(Step.advance) { Skip() }
                }
            })
            algorithm
        }
    }
}
