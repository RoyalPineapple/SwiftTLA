import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct ProjectedProgress {
    struct Position: Hashable, Sendable {
        let progress: Int
        let noise: Int
    }
    enum Step: String, CaseIterable { case toggle, advance }

    static var spec: TLASpec {
        #spec("ProjectedProgress") { scope in
            let position = scope.sharedVar(initial: Position(progress: 0, noise: 0))
            Do(Step.toggle) { Assign(position.noise, to: 1 - position.noise) }
            Do(Step.advance, when: position.progress == 0) { Assign(position.progress, to: 1) }
            WeakFairnessNext(on: position.progress)
            StrongFairnessNext(on: position.progress)
            let Complete = Temporal()
            Complete(.eventually(position.progress == 1))
        }
    }
}

@TLAModel
struct ProjectedStuttering {
    enum Step: String, CaseIterable { case toggle }

    static var spec: TLASpec {
        #spec("ProjectedStuttering") { scope in
            let progress = scope.sharedVar(initial: 0)
            let noise = scope.sharedVar(initial: 0)
            let toggle = Do(Step.toggle) { Assign(noise, to: 1 - noise) }
            toggle
            WeakFairness(toggle, on: progress)
            StrongFairness(toggle, on: progress)
            let Changed = Temporal()
            Changed(.eventually(noise == 1))
        }
    }
}
