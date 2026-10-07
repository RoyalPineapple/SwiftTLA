import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct AbstractValueModel {
    enum Step: String, CaseIterable { case stay }

    static var spec: TLASpec {
        #spec { scope in
            let value = scope.sharedVar(initial: 0)
            Do(Step.stay) { Assign(value, to: value) }
        }
    }
}

@TLAModel
struct InvalidGeneratedRefinementMapping {
    enum Step: String, CaseIterable { case stay }

    static var spec: TLASpec {
        #spec { scope in
            let count = scope.sharedVar(initial: 0)
            Do(Step.stay) { Assign(count, to: count) }
            let abstract = Instance(of: AbstractValueModel.self) {}
            abstract
            let Refines = Refinement(instance: abstract) {}
            Refines
        }
    }
}
