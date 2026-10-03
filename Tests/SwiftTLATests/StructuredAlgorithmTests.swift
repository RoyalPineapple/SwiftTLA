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

    struct CarState: Hashable, Sendable {
        let floor: Int
        let door: Door
    }

    static var spec: TLASpec {
        #spec("StructuredCar") {
            let structuredCar = Algorithm(label: "StructuredCar", scoped: { scope in
                let cars = scope.sharedVar(_name: "cars", initial: Function<Car, CarState>.literal(
                    (.north, CarState(floor: 1, door: .closed)),
                    (.south, CarState(floor: 2, door: .closed))
                ))

                Each(Car.all) { car in
                    Do(Step.open, when: cars[car].door == Door.closed) {
                        Assign(cars[car].door, to: Door.open)
                    }
                }
            })
            structuredCar
        }
    }
}

@Suite("Structured Algorithm")
struct StructuredAlgorithmTests {
    @Test("record-valued map updates survive #spec, lowering, and generated state")
    func generatedStateRetainsNestedTypedRecordUpdate() throws {
        var machine = try StructuredCarModel.makeMachine()
        let transition = try machine.send(.open(process: .north))

        #expect(transition.before.cars[.north]?.floor == 1)
        #expect(transition.before.cars[.north]?.door == .closed)
        #expect(transition.after.cars[.north]?.floor == 1)
        #expect(transition.after.cars[.north]?.door == .open)
        #expect(transition.after.cars[.south]?.floor == 2)
        #expect(transition.after.cars[.south]?.door == .closed)
    }

    @Test("function comprehensions retain typed record values through lowering and evaluation")
    func loweredFunctionComprehensionRetainsRecords() throws {
        let algorithm = Algorithm("StructuredComprehension", scoped: { scope in
            let cars = scope.sharedVar(_name: "cars",
                initial: Function<StructuredCarModel.Car, StructuredCarModel.CarState>.mapping { _ in
                    StructuredCarModel.CarState(floor: 4, door: .closed)
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
                  let record = StructuredCarModel.CarState(formalValue: value) else {
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
