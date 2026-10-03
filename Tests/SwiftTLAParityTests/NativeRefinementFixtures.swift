import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct NativeRefinementCounter {
    static var spec: TLASpec {
        #spec("NativeRefinementCounter") { scope in
            let abstract = TLASpec("AbstractPairCounter") {
                let value = Var<Pair<Int, Int>>("value")
                Variable(value, Pair<Int, Int>.literal(0, 0))
                SwiftTLA.Action("advance") {
                    value.becomes(Pair<Int, Int>.literal(value.first() + 1, 0)).when(value.first() < 2)
                }
                Constraint(value.first() < 1)
            }
            let count = scope.sharedVar(_name: "count", initial: 0)
            SwiftTLA.Action("advance") { count.becomes(count + 1).when(count < 4) }
            let instance = Instance("Counter", of: abstract)
            instance
            let Refines = Refinement(instance: instance,
                mappings: [.init(Var<Pair<Int, Int>>("value"), from: Pair<Int, Int>.literal(count / 2, 0))])
            Refines
        }
    }
}

@TLAModel
struct InvalidNativeRefinement {
    static var spec: TLASpec {
        #spec("InvalidNativeRefinement") { scope in
            let abstract = TLASpec("AbstractCounter") {
                let value = Var<Int>("value")
                Variable(value, 0)
                SwiftTLA.Action("advance") { value.becomes(value + 1).when(value < 2) }
            }
            let count = scope.sharedVar(_name: "count", in: 0...1)
            Invariant("BelowTwo") { count < 2 }
            Eventually("ReachesFour", count == 4)
            SwiftTLA.Action("advance") { count.becomes(count + 2).when(count < 2) }
            let instance = Instance("Counter", of: abstract)
            instance
            let Refines = Refinement(instance: instance, mappings: [.init(Var<Int>("value"), from: count)])
            Refines
        }
    }
}

@TLAModel
struct FairNativeRefinement {
    static var spec: TLASpec {
        #spec("FairNativeRefinement") { scope in
            let abstract = TLASpec("FairAbstractCounter") {
                let value = Var<Int>("value")
                Variable(value, 0)
                SwiftTLA.Action("advance") { value.becomes(value + 1).when(value < 2) }
                WeakFairnessNext()
            }
            let count = scope.sharedVar(_name: "count", initial: 0)
            SwiftTLA.Action("advance") { count.becomes(count + 1).when(count < 2) }
            let instance = Instance("Counter", of: abstract)
            instance
            let Refines = Refinement(instance: instance, mappings: [.init(Var<Int>("value"), from: count)])
            Refines
        }
    }
}

@TLAModel
struct FairConcreteRefinement {
    static var spec: TLASpec {
        #spec("FairConcreteRefinement") { scope in
            let abstract = TLASpec("FairAbstractCounter") {
                let value = Var<Int>("value")
                Variable(value, 0)
                SwiftTLA.Action("advance") { value.becomes(value + 1).when(value < 2) }
                WeakFairnessNext()
            }
            let count = scope.sharedVar(_name: "count", initial: 0)
            SwiftTLA.Action("advance") { count.becomes(count + 1).when(count < 2) }
            WeakFairnessNext()
            let instance = Instance("Counter", of: abstract)
            instance
            let Refines = Refinement(instance: instance, mappings: [.init(Var<Int>("value"), from: count)])
            Refines
        }
    }
}

@TLAModel
struct StoppedConcreteRefinement {
    static var spec: TLASpec {
        #spec("StoppedConcreteRefinement") { scope in
            let abstract = TLASpec("FairAbstractCounter") {
                let value = Var<Int>("value")
                Variable(value, 0)
                SwiftTLA.Action("advance") { value.becomes(value + 1).when(value < 2) }
                WeakFairnessNext()
            }
            let count = scope.sharedVar(_name: "count", initial: 0)
            SwiftTLA.Action("advance") { count.becomes(count + 1).when(count < 1) }
            WeakFairnessNext()
            let instance = Instance("Counter", of: abstract)
            instance
            let Refines = Refinement(instance: instance, mappings: [.init(Var<Int>("value"), from: count)])
            Refines
        }
    }
}
