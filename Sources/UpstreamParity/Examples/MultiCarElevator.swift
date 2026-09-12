import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct MultiCarElevator: Sendable {
    package enum PersonID: String, CaseIterable, FiniteTLAValueDomain {
        case alice, bob

        package static var defaultValue: Self { .alice }
        package static let finiteValues = allCases
    }

    package enum CarID: String, CaseIterable, FiniteTLAValueDomain {
        case carA, carB

        package static var defaultValue: Self { .carA }
        package static let finiteValues = allCases
    }

    package enum FloorID: Int, CaseIterable, FiniteTLAValueDomain {
        case ground = 0, middle = 1, top = 2

        package static var defaultValue: Self { .ground }
        package static let finiteValues = allCases
    }

    package enum Direction: String, CaseIterable, FiniteTLAValueDomain {
        case up, down

        package static var defaultValue: Self { .up }
        package static let finiteValues = allCases
    }

    package struct CarFields {
        package let floor: FloorID
        package let doorsOpen: Bool
        package let rider: String
    }

    package enum CarSchema: TLARecordSchema {
        package typealias Fields = CarFields

        package static let fields: [TLARecordFieldDeclaration<Self>] = [
            .init(floor, default: FloorID.ground),
            .init(doorsOpen, default: false),
            .init(rider, default: "none"),
        ]

        package static func fieldName<Value>(for field: KeyPath<CarFields, Value>) -> String? {
            let key = field as AnyKeyPath
            if key == \CarFields.floor { return "floor" }
            if key == \CarFields.doorsOpen { return "doorsOpen" }
            if key == \CarFields.rider { return "rider" }
            return nil
        }

        package static let floor = field(\CarFields.floor)
        package static let doorsOpen = field(\CarFields.doorsOpen)
        package static let rider = field(\CarFields.rider)
    }

    package struct CallFields {
        package let person: PersonID
        package let floor: FloorID
        package let direction: Direction
    }

    package enum CallSchema: TLARecordSchema {
        package typealias Fields = CallFields

        package static let fields: [TLARecordFieldDeclaration<Self>] = [
            .init(person, default: PersonID.alice),
            .init(floor, default: FloorID.ground),
            .init(direction, default: Direction.up),
        ]

        package static func fieldName<Value>(for field: KeyPath<CallFields, Value>) -> String? {
            let key = field as AnyKeyPath
            if key == \CallFields.person { return "person" }
            if key == \CallFields.floor { return "floor" }
            if key == \CallFields.direction { return "direction" }
            return nil
        }

        package static let person = field(\CallFields.person)
        package static let floor = field(\CallFields.floor)
        package static let direction = field(\CallFields.direction)
    }

    package static var spec: TLASpec {
        #spec("MultiCarElevator") { scope in
            let cars = scope.sharedVar("cars", initial: Function<CarID, Record<CarSchema>>.literal(
                (.carA, Record<CarSchema>.literal(
                    .init(CarSchema.floor, FloorID.ground),
                    .init(CarSchema.doorsOpen, false),
                    .init(CarSchema.rider, "none")
                )),
                (.carB, Record<CarSchema>.literal(
                    .init(CarSchema.floor, FloorID.top),
                    .init(CarSchema.doorsOpen, false),
                    .init(CarSchema.rider, "none")
                ))
            ))
            let calls = scope.sharedVar("calls", initial: SetExpr<Record<CallSchema>>())
            let lastMoveDoorClosed = scope.sharedVar("lastMoveDoorClosed", initial: true)
            let floors = SetExpr<FloorID>.literal(.ground, .middle, .top)
            let riders = SetExpr<String>.literal("none", "alice", "bob")
            let person = ActionParameter("person", values: PersonID.finiteValues)
            let car = ActionParameter("car", values: CarID.finiteValues)
            let floor = ActionParameter("floor", values: FloorID.finiteValues)
            let direction = ActionParameter("direction", values: Direction.finiteValues)

            Constraint(calls.cardinality <= 1)
            Invariant("TypeOK") {
                floors.contains(cars[.carA][CarSchema.floor])
                    && floors.contains(cars[.carB][CarSchema.floor])
                    && riders.contains(cars[.carA][CarSchema.rider])
                    && riders.contains(cars[.carB][CarSchema.rider])
            }
            Invariant("FloorBounds") {
                cars[.carA][CarSchema.floor].assuming(Int.self) >= 0
                    && cars[.carA][CarSchema.floor].assuming(Int.self) <= 2
                    && cars[.carB][CarSchema.floor].assuming(Int.self) >= 0
                    && cars[.carB][CarSchema.floor].assuming(Int.self) <= 2
            }
            Invariant("ClosedDoorMovement") { lastMoveDoorClosed == true }
            Invariant("NoDoubleAssignment") {
                cars[.carA][CarSchema.rider] == "none"
                    || cars[.carB][CarSchema.rider] == "none"
                    || cars[.carA][CarSchema.rider] != cars[.carB][CarSchema.rider]
            }

            SwiftTLA.Action("request", parameters: [person, floor, direction]) {
                let call = Record<CallSchema>.literal(
                    .init(CallSchema.person, person.expr),
                    .init(CallSchema.floor, floor.expr),
                    .init(CallSchema.direction, direction.expr)
                )
                !calls.contains(call) && calls.becomes(calls.inserting(call))
            }
            SwiftTLA.Action("assign", parameters: [person, car, direction]) {
                calls.cardinality == 1
                    && cars[.carA][CarSchema.rider] != person.assuming(String.self)
                    && cars[.carB][CarSchema.rider] != person.assuming(String.self)
                    && cars[car][CarSchema.rider] == "none"
                    && cars.becomes(cars.updating(car, to:
                        cars[car].updating(CarSchema.rider, to: person.assuming(String.self))))
            }
            SwiftTLA.Action("move", parameters: [car, direction, floor]) {
                cars[car][CarSchema.doorsOpen] == false
                    && cars[car][CarSchema.floor] != floor.expr
                    && cars.becomes(cars.updating(car, to: cars[car].updating(CarSchema.floor, to: floor.expr)))
                    && lastMoveDoorClosed.becomes(true)
            }
            SwiftTLA.Action("openDoor", parameters: [car, floor, direction]) {
                cars[car][CarSchema.doorsOpen] == false
                    && cars.becomes(cars.updating(car, to: cars[car].updating(CarSchema.doorsOpen, to: true)))
            }
            SwiftTLA.Action("board", parameters: [person, car, floor]) {
                cars[car][CarSchema.doorsOpen] == true
                    && cars[car][CarSchema.rider] == person.assuming(String.self)
                    && calls.becomes(calls.removing(Record<CallSchema>.literal(
                        .init(CallSchema.person, person.expr),
                        .init(CallSchema.floor, floor.expr),
                        .init(CallSchema.direction, Direction.up)
                    )))
            }
            SwiftTLA.Action("closeDoor", parameters: [car, floor, direction]) {
                cars[car][CarSchema.doorsOpen] == true
                    && cars.becomes(cars.updating(car, to: cars[car].updating(CarSchema.doorsOpen, to: false)))
            }
            SwiftTLA.Action("completeRide", parameters: [person, car, floor]) {
                cars[car][CarSchema.doorsOpen] == true
                    && cars[car][CarSchema.rider] == person.assuming(String.self)
                    && cars[car][CarSchema.floor] == floor.expr
                    && cars.becomes(cars.updating(car, to: cars[car].updating(CarSchema.rider, to: "none")))
            }
        }
    }
}
