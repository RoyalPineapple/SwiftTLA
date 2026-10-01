import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct Counter {
    enum Step: String, CaseIterable {
        case advance
    }

    enum Node: String, FiniteTLAValueDomain {
        case only

        static var defaultValue: Self { .only }
        static let finiteValues: [Node] = [.only]

        var tlaValue: TLAValue { .string(rawValue) }
    }

    struct Car: Hashable, Sendable {
        let floor: Int
        let doorsOpen: Bool
    }

    enum CarID: String, FiniteTLAValueDomain {
        case one
        case two

        static var defaultValue: Self { .one }
        static let finiteValues: [CarID] = [.one, .two]
    }

    static var spec: TLASpec {
        #spec("Counter") {
            Algorithm("Counter", scoped: { scope in
                let value = scope.sharedVar(_name: "value", initial: 0)
                let cars = scope.sharedVar(_name: "cars", initial: Function<CarID, Car>.literal(
                    (.one, Car(floor: 1, doorsOpen: false)),
                    (.two, Car(floor: 2, doorsOpen: false))
                ))
                Each(Node.all, scoped: { _, scope in
                    let visits = scope.localVar(_name: "visits", initial: 0)
                    Do(Step.advance, when: value < 1) {
                        Assign(value, to: value + 1)
                        Assign(cars[.one].floor, to: 2)
                        Assign(visits, to: visits + 1)
                        Stop()
                    }
                })
            })
        }
    }
}

var counter = try Counter.makeMachine()
let transition = try counter.send(.advance)
guard transition.after.value == 1,
      transition.after.cars[.one]?.floor == 2,
      transition.after.cars[.one]?.doorsOpen == false else {
    throw FixtureError.invalidTransition
}

private enum FixtureError: Error {
    case invalidTransition
}
