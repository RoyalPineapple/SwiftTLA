import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct MultiCarElevator: Sendable {
    package enum PersonID: String, CaseIterable { case alice, bob }
    package enum CarID: String, CaseIterable { case carA, carB }
    package enum FloorID: Int, CaseIterable { case ground = 0, middle = 1, top = 2 }
    package enum Direction: String, CaseIterable { case up, down }
    package enum Step: String, CaseIterable {
        case request, assign, move, openDoor, board, closeDoor, completeRide
    }

    package struct Car: Hashable, Sendable {
        package let floor: FloorID
        package let doorsOpen: Bool
        package let rider: String
    }

    package struct Call: Hashable, Sendable {
        package let person: PersonID
        package let floor: FloorID
        package let direction: Direction
    }

    package static var spec: TLASpec {
        #spec("MultiCarElevator") { scope in
            let cars: SharedVariable<[CarID: Car]> = scope.sharedVar(initial: [
                .carA: Car(floor: .ground, doorsOpen: false, rider: "none"),
                .carB: Car(floor: .top, doorsOpen: false, rider: "none")
            ])
            let calls = scope.sharedVar(initial: Set<Call>())
            let lastMoveDoorClosed = scope.sharedVar(initial: true)
            let riders = Set<String>(["none", "alice", "bob"])
            let TypeOK = Invariant()
            let FloorBounds = Invariant()
            let ClosedDoorMovement = Invariant()
            let NoDoubleAssignment = Invariant()

            Constraint(calls.cardinality <= 1)
            TypeOK {
                FloorID.all.contains(cars[.carA].floor)
                    && FloorID.all.contains(cars[.carB].floor)
                    && riders.contains(cars[.carA].rider)
                    && riders.contains(cars[.carB].rider)
            }
            FloorBounds {
                cars[.carA].floor.assuming(Int.self) >= 0
                    && cars[.carA].floor.assuming(Int.self) <= 2
                    && cars[.carB].floor.assuming(Int.self) >= 0
                    && cars[.carB].floor.assuming(Int.self) <= 2
            }
            ClosedDoorMovement { lastMoveDoorClosed == true }
            NoDoubleAssignment {
                cars[.carA].rider == "none"
                    || cars[.carB].rider == "none"
                    || cars[.carA].rider != cars[.carB].rider
            }

            Do(Step.request, over: PersonID.all, FloorID.all, Direction.all) { person, floor, direction in
                let call = Call.expression(person: person, floor: floor, direction: direction)
                When(!calls.contains(call))
                Assign(calls, to: calls.inserting(call))
            }
            Do(Step.assign, over: PersonID.all, CarID.all, Direction.all) { person, car, direction in
                When(calls.cardinality == 1
                    && cars[.carA].rider != person.assuming(String.self)
                    && cars[.carB].rider != person.assuming(String.self)
                    && cars[car].rider == "none")
                Assign(cars[car].rider, to: person.assuming(String.self))
            }
            Do(Step.move, over: CarID.all, Direction.all, FloorID.all) { car, direction, floor in
                When(cars[car].doorsOpen == false && cars[car].floor != floor)
                Assign(cars[car].floor, to: floor)
                Assign(lastMoveDoorClosed, to: true)
            }
            Do(Step.openDoor, over: CarID.all, FloorID.all, Direction.all) { car, floor, direction in
                When(cars[car].doorsOpen == false)
                Assign(cars[car].doorsOpen, to: true)
            }
            Do(Step.board, over: PersonID.all, CarID.all, FloorID.all) { person, car, floor in
                When(cars[car].doorsOpen == true && cars[car].rider == person.assuming(String.self))
                Assign(calls, to: calls.removing(Call.expression(person: person, floor: floor, direction: Direction.up)))
            }
            Do(Step.closeDoor, over: CarID.all, FloorID.all, Direction.all) { car, floor, direction in
                When(cars[car].doorsOpen == true)
                Assign(cars[car].doorsOpen, to: false)
            }
            Do(Step.completeRide, over: PersonID.all, CarID.all, FloorID.all) { person, car, floor in
                When(cars[car].doorsOpen == true
                    && cars[car].rider == person.assuming(String.self)
                    && cars[car].floor == floor)
                Assign(cars[car].rider, to: "none")
            }
        }
    }
}
