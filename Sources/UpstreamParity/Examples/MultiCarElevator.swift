import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct MultiCarElevator: Sendable {
    package enum PersonID: String, CaseIterable, NoneEncodedOptionalElement { case alice, bob }
    package enum CarID: String, CaseIterable { case carA, carB }
    package enum FloorID: Int, CaseIterable { case ground = 0, middle = 1, top = 2 }
    package enum Direction: String, CaseIterable { case up, down }
    package enum Step: String, CaseIterable {
        case request, assign, move, openDoor, board, closeDoor, completeRide
    }

    package struct Car: Hashable, Sendable {
        package let floor: FloorID
        package let doorsOpen: Bool
        package let rider: PersonID?
    }

    package struct Call: Hashable, Sendable {
        package let person: PersonID
        package let floor: FloorID
        package let direction: Direction
    }

    package static var spec: TLASpec {
        #spec("MultiCarElevator") { scope in
            let cars: SharedVariable<[CarID: Car]> = scope.sharedVar(initial: [
                .carA: Car(floor: .ground, doorsOpen: false, rider: nil),
                .carB: Car(floor: .top, doorsOpen: false, rider: nil)
            ])
            let calls = scope.sharedVar(initial: Set<Call>())
            let lastMoveDoorClosed = scope.sharedVar(initial: true)
            let riders = Set<PersonID?>([nil, .alice, .bob])

            Constraint(calls.count <= 1)
            Invariant("TypeOK") {
                FloorID.all.contains(cars[.carA].floor)
                    && FloorID.all.contains(cars[.carB].floor)
                    && riders.contains(cars[.carA].rider)
                    && riders.contains(cars[.carB].rider)
            }
            Invariant("FloorBounds") {
                cars[.carA].floor.assuming(Int.self) >= 0
                    && cars[.carA].floor.assuming(Int.self) <= 2
                    && cars[.carB].floor.assuming(Int.self) >= 0
                    && cars[.carB].floor.assuming(Int.self) <= 2
            }
            Invariant("ClosedDoorMovement") { lastMoveDoorClosed == true }
            Invariant("NoDoubleAssignment") {
                cars[.carA].rider == nil
                    || cars[.carB].rider == nil
                    || cars[.carA].rider != cars[.carB].rider
            }

            Do(Step.request, over: PersonID.all, FloorID.all, Direction.all) { person, floor, direction in
                let call = Call.expression(person: person, floor: floor, direction: direction)
                When(!calls.contains(call))
                calls.insert(call)
            }
            Do(Step.assign, over: PersonID.all, CarID.all, Direction.all) { person, car, direction in
                When(calls.count == 1
                    && cars[.carA].rider != person
                    && cars[.carB].rider != person
                    && cars[car].rider == nil)
                cars[car].rider.set(person)
            }
            Do(Step.move, over: CarID.all, Direction.all, FloorID.all) { car, direction, floor in
                When(cars[car].doorsOpen == false && cars[car].floor != floor)
                cars[car].floor.set(floor)
                lastMoveDoorClosed.set(true)
            }
            Do(Step.openDoor, over: CarID.all, FloorID.all, Direction.all) { car, floor, direction in
                When(cars[car].doorsOpen == false)
                cars[car].doorsOpen.set(true)
            }
            Do(Step.board, over: PersonID.all, CarID.all, FloorID.all) { person, car, floor in
                When(cars[car].doorsOpen == true && cars[car].rider == person)
                calls.remove(Call.expression(person: person, floor: floor, direction: Direction.up))
            }
            Do(Step.closeDoor, over: CarID.all, FloorID.all, Direction.all) { car, floor, direction in
                When(cars[car].doorsOpen == true)
                cars[car].doorsOpen.set(false)
            }
            Do(Step.completeRide, over: PersonID.all, CarID.all, FloorID.all) { person, car, floor in
                When(cars[car].doorsOpen == true
                    && cars[car].rider == person
                    && cars[car].floor == floor)
                cars[car].rider.set(nil)
            }
            let MultiCarElevator = Validation {}.checkingDeadlock(false)
            MultiCarElevator
        }
    }
}
