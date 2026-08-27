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

    struct CarFields {
        let floor: Int
        let doorsOpen: Bool
    }

    enum CarSchema: TLARecordSchema {
        typealias Fields = CarFields

        static let fieldNames: Set<String> = ["doorsOpen", "floor"]
        static let defaultRecord: TLAValue = .record(["doorsOpen": .bool(false), "floor": .int(0)])

        static func fieldName<Value>(for field: KeyPath<CarFields, Value>) -> String? {
            let key = field as AnyKeyPath
            if key == \CarFields.floor { return "floor" }
            if key == \CarFields.doorsOpen { return "doorsOpen" }
            return nil
        }

        static let floor = field(\CarFields.floor)
        static let doorsOpen = field(\CarFields.doorsOpen)
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
                let value = scope.sharedVar("value", initial: 0)
                let cars = scope.sharedVar("cars", initial: Function<CarID, Record<CarSchema>>.literal(
                    (.one, Record<CarSchema>.literal(.init(CarSchema.floor, 1), .init(CarSchema.doorsOpen, false))),
                    (.two, Record<CarSchema>.literal(.init(CarSchema.floor, 2), .init(CarSchema.doorsOpen, false)))
                ))
                Each(Node.all, scoped: { _, scope in
                    let visits = scope.localVar("visits", initial: 0)
                    Do(Step.advance) {
                        When(value < 1)
                        Assign(value, to: value + 1)
                        Assign(cars, to: cars.updating(.one) { car in
                            car.updating(CarSchema.floor, to: 2)
                        })
                        Assign(visits, to: visits + 1)
                        Stop()
                    }
                })
            })
        }
    }
}

var counter = try Counter.makeMachine()
let result = try counter.send(.advance)
guard result.after.value == 1,
      result.after.cars[.one][Counter.CarSchema.floor] == 2 else {
    throw FixtureError.invalidTransition
}

private enum FixtureError: Error {
    case invalidTransition
}
