import Testing
import SwiftTLA
import SwiftTLAMacros

/// The smallest end-to-end witness: a finite map holds typed records, an
/// atomic action updates one nested field, and generated state stays typed.
@TLAModel
private struct StructuredCarModel {
    enum Car: String, CaseIterable, FiniteDomainKey {
        case north
        case south

        static let formalDomain = allCases
        static let formalTypeIdentity = FormalTypeIdentity(rawValue: "test.structured-car")

        var tlaValue: TLAValue { .string(rawValue) }
    }

    enum Door: String, CaseIterable, FiniteDomainKey {
        case closed
        case open

        static let formalDomain = allCases
        static let formalTypeIdentity = FormalTypeIdentity(rawValue: "test.structured-door")

        var tlaValue: TLAValue { .string(rawValue) }
    }

    struct CarFields {
        let floor: Int
        let door: Door
    }

    enum CarRecord: TLARecordSchema {
        typealias Fields = CarFields

        static let fieldNames: Set<String> = ["floor", "door"]
        static let defaultRecord: TLAValue = .record([
            "floor": .int(1),
            "door": .string(Door.closed.rawValue)
        ])

        static func fieldName<Value>(for field: KeyPath<CarFields, Value>) -> String? {
            let key = field as AnyKeyPath
            if key == \CarFields.floor { return "floor" }
            if key == \CarFields.door { return "door" }
            return nil
        }

        static let floor = field(\CarFields.floor)
        static let door = field(\CarFields.door)
    }

    static var spec: TLASpec {
        #spec("StructuredCar") {
            Algorithm("StructuredCar") {
                let cars = SharedVar(initial: Function<Car, Record<CarRecord>>.literal(
                    (.north, Record.literal(.init(CarRecord.floor, 1), .init(CarRecord.door, .closed))),
                    (.south, Record.literal(.init(CarRecord.floor, 2), .init(CarRecord.door, .closed)))
                ))

                Each(Car.all) { car in
                    Do("open") {
                        When(cars[car][CarRecord.door] == .closed)
                        Assign(cars, to: cars.updating(car) { vehicle in
                            vehicle.updating(CarRecord.door, to: .open)
                        })
                    }
                }
            }
        }
    }
}

@Suite("Structured Algorithm")
struct StructuredAlgorithmTests {
    @Test("record-valued map updates survive #spec, lowering, and generated state")
    func generatedStateRetainsNestedTypedRecordUpdate() throws {
        StructuredCarModel._checkParserTree()

        var model = try StructuredCarModel.makeMachine()
        let result = try model.apply(.open(process: .north))

        #expect(result.before.cars[.north][StructuredCarModel.CarRecord.door] == .closed)
        #expect(result.after.cars[.north][StructuredCarModel.CarRecord.door] == .open)
        #expect(result.after.cars[.north][StructuredCarModel.CarRecord.floor] == 1)
        #expect(result.after.cars[.south][StructuredCarModel.CarRecord.door] == .closed)
    }

    @Test("function comprehensions retain typed record values through lowering and evaluation")
    func loweredFunctionComprehensionRetainsRecords() throws {
        let algorithm = Algorithm("StructuredComprehension") {
            let cars = SharedVar(
                "cars",
                initial: Function<StructuredCarModel.Car, Record<StructuredCarModel.CarRecord>>.mapping { _ in
                    Record.literal(
                        .init(StructuredCarModel.CarRecord.floor, 4),
                        .init(StructuredCarModel.CarRecord.door, .closed)
                    )
                }
            )
            cars
            Do("hold") { Assign(cars, to: cars.expr) }
        }

        let spec = try algorithm.lower()
        let initial = try #require(computeInitialStates(spec).first)

        for car in StructuredCarModel.Car.allCases {
            let record = try #require(Record<StructuredCarModel.CarRecord>(formalValue: StateExpr.functionApply(
                .variable("cars"),
                .value(car.tlaValue)
            ).evaluate(in: initial)))
            #expect(record[StructuredCarModel.CarRecord.floor] == 4)
            #expect(record[StructuredCarModel.CarRecord.door] == .closed)
        }
    }
}
