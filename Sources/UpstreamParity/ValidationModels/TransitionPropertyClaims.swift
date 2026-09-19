import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct TransitionPropertyClaims {
    package struct Value: Hashable, Sendable { package let count: Int; package let marker: Int }
    package enum Step: String, CaseIterable { case advance, stay }

    package static var spec: TLASpec {
        #spec("TransitionPropertyClaims") { scope in
            let limit = scope.parameter(as: Int.self, in: 2...3)
            let value = scope.sharedVar(in: IntRange(0, through: 1).mapping { count in
                Value.expression(count: count, marker: 7)
            })
            let increases = Temporal()
            let preservesMarker = Temporal()
            let preservesParity = Temporal()
            let selectedStuttering = Temporal()
            let composed = Temporal()
            Do(Step.advance, when: value.count < limit) {
                Assign(value, to: Value.expression(count: value.count + 1, marker: value.marker))
            }
            Do(Step.stay, when: value.count == limit) { Assign(value, to: value) }
            WeakFairnessNext()
            increases(.alwaysStep(on: value) { before, after in
                1 / (after.count - before.count) > 0 && after.count > before.count
            })
            preservesMarker(.alwaysStep(on: value) { before, after in before.marker == after.marker })
            preservesParity(.alwaysStep(on: value.count) { before, after in before % 2 == after % 2 })
            selectedStuttering(.alwaysStep(on: value.marker) { before, after in before != after })
            composed(.conditional(value.count == 0,
                then: .all([
                    .alwaysStep(on: value.count + 1) { before, after in after > before },
                    .eventually(value.count == limit)
                ]),
                else: .eventually(value.count == 1)))
            Validation("Two") { Bind(limit, to: 2) }.expect(preservesParity, .violated)
            Validation("Three") { Bind(limit, to: 3) }.expect(preservesParity, .violated)
        }
    }
}
