import Testing
@testable import SwiftTLA
import SwiftTLAMacros

/// The smallest end-to-end witness: a finite map holds typed records, an
/// atomic action updates one nested field, and generated state stays typed.
@TLAModel
private struct StructuredCarModel {
    enum Step: String, CaseIterable { case open }

    enum Car: String, CaseIterable, FiniteTLAValueDomain {
        case north
        case south

        static var defaultValue: Self { .north }
        static let finiteValues = allCases

        var tlaValue: TLAValue { .string(rawValue) }
    }

    enum Door: String, CaseIterable, FiniteTLAValueDomain {
        case closed
        case open

        static var defaultValue: Self { .closed }
        static let finiteValues = allCases

        var tlaValue: TLAValue { .string(rawValue) }
    }

    struct CarFields {
        let floor: Int
        let door: Door
    }

    enum CarRecord: TLARecordSchema {
        typealias Fields = CarFields

        static func fieldName<Value>(for field: KeyPath<CarFields, Value>) -> String? {
            let key = field as AnyKeyPath
            if key == \CarFields.floor { return "floor" }
            if key == \CarFields.door { return "door" }
            return nil
        }

        static let floor = field(\CarFields.floor)
        static let door = field(\CarFields.door)
        static let fields = [
            TLARecordFieldDeclaration(floor, default: 1),
            TLARecordFieldDeclaration(door, default: Door.closed)
        ]
    }

    static var spec: TLASpec {
        #spec("StructuredCar") {
            Algorithm("StructuredCar", scoped: { scope in
                let cars = scope.sharedVar("cars", initial: Function<Car, Record<CarRecord>>.literal(
                    (.north, Record.literal(.init(CarRecord.floor, 1), .init(CarRecord.door, Door.closed))),
                    (.south, Record.literal(.init(CarRecord.floor, 2), .init(CarRecord.door, Door.closed)))
                ))

                Each(Car.all) { car in
                    Do(Step.open) {
                        When(cars[car][CarRecord.door] == Door.closed)
                        Assign(cars, to: cars.updating(car) { vehicle in
                            vehicle.updating(CarRecord.door, to: Door.open)
                        })
                    }
                }
            })
        }
    }
}

@Suite("Structured Algorithm")
struct StructuredAlgorithmTests {
    @Test("record-valued map updates survive #spec, lowering, and generated state")
    func generatedStateRetainsNestedTypedRecordUpdate() throws {
        var machine = try StructuredCarModel.makeMachine()
        let transition = try machine.send(.open(process: .north))

        #expect(transition.before.cars[.north]?.tlaValue == .record([
            "floor": .int(1),
            "door": .string(StructuredCarModel.Door.closed.rawValue)
        ]))
        #expect(transition.after.cars[.north]?.tlaValue == .record([
            "floor": .int(1),
            "door": .string(StructuredCarModel.Door.open.rawValue)
        ]))
        #expect(transition.after.cars[.south]?.tlaValue == .record([
            "floor": .int(2),
            "door": .string(StructuredCarModel.Door.closed.rawValue)
        ]))
    }

    @Test("function comprehensions retain typed record values through lowering and evaluation")
    func loweredFunctionComprehensionRetainsRecords() throws {
        let algorithm = Algorithm("StructuredComprehension", scoped: { scope in
            let cars = scope.sharedVar(
                "cars",
                initial: Function<StructuredCarModel.Car, Record<StructuredCarModel.CarRecord>>.mapping { _ in
                    Record.literal(
                        .init(StructuredCarModel.CarRecord.floor, 4),
                        .init(StructuredCarModel.CarRecord.door, .closed)
                    )
                }
            )
            Do(TestControlLabel.hold) { Assign(cars, to: cars.expr) }
        })

        let spec = try loweredSourceSpecification(algorithm)
        let compilation = try spec.compile()
        let initial = try #require(try CompiledRuntime(compilation: compilation).initialStates().first)
        let cars = try #require(compilation.layout.testVariableID(named: "cars"))
        guard case .function(let values) = try initial.value(for: cars).rendered(using: compilation.layout) else {
            Issue.record("Expected a formal function for cars.")
            return
        }

        for car in StructuredCarModel.Car.allCases {
            guard let value = values[car.tlaValue],
                  let record = Record<StructuredCarModel.CarRecord>(formalValue: value) else {
                Issue.record("Expected a typed car record.")
                return
            }
            #expect(record.tlaValue == .record([
                "floor": .int(4),
                "door": .string(StructuredCarModel.Door.closed.rawValue)
            ]))
        }
    }
}
