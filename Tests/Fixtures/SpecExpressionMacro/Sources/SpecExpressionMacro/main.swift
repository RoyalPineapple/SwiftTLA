import SwiftTLA
import SwiftTLAMacros

@TLAModel
struct Counter {
    enum Node: String, FiniteDomainKey {
        case only

        static let formalDomain: [Node] = [.only]
        static let formalTypeIdentity = FormalTypeIdentity(rawValue: "fixture.spec-expression-node")

        var tlaValue: TLAValue { .string(rawValue) }
    }

    struct CarFields {
        let floor: Int
        let doorsOpen: Bool
    }

    enum CarSchema: TLARecordSchema {
        typealias Fields = CarFields

        static let fieldNames: Set<String> = ["doorsOpen", "floor"]

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

        static let finiteValues: [CarID] = [.one, .two]
    }

    static var spec: TLASpec {
        #spec("Counter") {
            Algorithm("Counter") {
                let value = SharedVar(initial: 0)
                let cars = SharedVar(initial: Function<CarID, Record<CarSchema>>.literal(
                    (.one, Record<CarSchema>.literal(.init(CarSchema.floor, 1), .init(CarSchema.doorsOpen, false))),
                    (.two, Record<CarSchema>.literal(.init(CarSchema.floor, 2), .init(CarSchema.doorsOpen, false)))
                ))
                Each(Node.all) { _ in
                    let visits = LocalVar(initial: 0)
                    Do("advance") {
                        When(value < 1)
                        Assign(value, to: value + 1)
                        Assign(cars, to: cars.updating(.one) { car in
                            car.updating(CarSchema.floor, to: 2)
                        })
                        Assign(visits, to: visits + 1)
                        Stop()
                    }
                }
            }
        }
    }
}

var counter = Counter()
let result = try counter.apply(.advance(process: .only))
precondition(result.after.value == 1)
