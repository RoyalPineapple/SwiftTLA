// People call elevators, board together, and leave at their destination. Dispatch picks a closest eligible car.
// https://github.com/tlaplus/Examples/blob/ceeaa904140e3e03781cb2a79cd6c6d8b8b08e10/specifications/MultiCarElevator/Elevator.tla

import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct MultiCarElevator: Sendable {
    package enum PersonID: String, CaseIterable, FiniteTLAValueDomain {
        case p1, p2, p3
        package static var defaultValue: Self { .p1 }
        package static let finiteValues = allCases
        package var tlaValue: TLAValue { .constant(rawValue) }
    }

    package enum CarID: String, CaseIterable, FiniteTLAValueDomain {
        case e1, e2, e3
        package static var defaultValue: Self { .e1 }
        package static let finiteValues = allCases
        package var tlaValue: TLAValue { .constant(rawValue) }
    }

    package typealias Location = OneOf<Int, CarID>
    package struct Rider: Hashable, Sendable {
        package let location: Location
        package let destination: Int
        package let waiting: Bool
    }
    package struct Car: Hashable, Sendable {
        package let floor: Int
        package let direction: String
        package let doorsOpen: Bool
        package let buttonsPressed: Set<Int>
    }
    package struct Call: Hashable, Sendable {
        package let floor: Int
        package let direction: String
    }
    package struct LivenessSubject: Hashable, Sendable {
        package let floor: Int
        package let direction: String
        package let person: PersonID
    }

    private enum Step: String, CaseIterable {
        case pickNewDestination = "PickNewDestination"
        case callElevator = "CallElevator"
        case openElevatorDoors = "OpenElevatorDoors"
        case enterElevator = "EnterElevator"
        case exitElevator = "ExitElevator"
        case closeElevatorDoors = "CloseElevatorDoors"
        case moveElevator = "MoveElevator"
        case stopElevator = "StopElevator"
        case dispatchElevator = "DispatchElevator"
    }

    package static var spec: TLASpec {
        #spec("Elevator") { scope in
            Extends(.integers)
            let Person = scope.parameter(as: Set<PersonID>.self, in: Subsets(of: PersonID.all.assuming(Set<PersonID>.self)))
            let Elevator = scope.parameter(as: Set<CarID>.self, in: Subsets(of: CarID.all.assuming(Set<CarID>.self)))
            let FloorCount = scope.parameter(as: Int.self, in: 1...5)
            let Floor = IntRange(1, through: FloorCount)
            let Direction = Set<String>(["Up", "Down"])
            let ElevatorCall = Floor.flatMapping { f in Direction.mapping { d in Call.expression(floor: f, direction: d) } }
            let initialRiders = Floor.flatMapping { f in Floor.mapping { dest in
                Rider.expression(location: Location.first(f), destination: dest, waiting: false)
            } }
            let initialCars = Floor.mapping { f in Car.expression(floor: f, direction: "Stationary",
                doorsOpen: false, buttonsPressed: Set<Int>()) }
            let PersonState: SharedVariable<[PersonID: Rider]> = scope.sharedVar(initiallyIn: Functions(from: Person, to: initialRiders))
            let ActiveElevatorCalls = scope.sharedVar(initial: Set<Call>())
            let ElevatorState: SharedVariable<[CarID: Car]> = scope.sharedVar(initiallyIn: Functions(from: Elevator, to: initialCars))

            FormalDefinition("GetDistance", taking: Int.self, Int.self) { a, b -> Expr<Int> in
                If(a > b, then: a - b, else: b - a)
            }
            FormalDefinition("GetDirection", taking: Int.self, Int.self) { current, destination -> Expr<String> in
                If(destination > current, then: "Up", else: "Down")
            }
            FormalDefinition("CanServiceCall", taking: CarID.self, Call.self) { e, c -> Expr<Bool> in
                ElevatorState[e].floor == c.floor && ElevatorState[e].direction == c.direction
            }
            FormalDefinition("PeopleWaiting", taking: Int.self, String.self) { f, d -> Expr<Set<PersonID>> in
                Person.filter { p in PersonState[p].location == Location.first(f) && PersonState[p].waiting
                    && FormalCall(as: String.self, "GetDirection", f, PersonState[p].destination) == d }
            }
            FormalDefinition("GettingOff", taking: CarID.self) { e -> Expr<Set<PersonID>> in
                Person.filter { p in PersonState[p].location == Location.second(e)
                    && PersonState[p].destination == ElevatorState[e].floor }
            }
            FormalDefinition("OpenRequested", taking: CarID.self) { e -> Expr<Bool> in
                ActiveElevatorCalls.contains { c in FormalCall(as: Bool.self, "CanServiceCall", e, c) }
                    || ElevatorState[e].buttonsPressed.contains(ElevatorState[e].floor)
            }

            Do(Step.pickNewDestination, over: Person) { p in
                When(!PersonState[p].waiting && Floor.contains { f in PersonState[p].location == Location.first(f) })
                With(Floor) { f in
                    When(PersonState[p].location != Location.first(f))
                    PersonState[p].destination.set(f)
                }
            }
            let callElevator = Do(Step.callElevator, over: Person) { p in
                When(!PersonState[p].waiting && PersonState[p].location != Location.first(PersonState[p].destination))
                let f = PersonState[p].location.assuming(Int.self)
                let call = Call.expression(floor: f, direction: FormalCall(as: String.self, "GetDirection", f, PersonState[p].destination))
                If(!Elevator.contains { e in FormalCall(as: Bool.self, "CanServiceCall", e, call) && ElevatorState[e].doorsOpen }) {
                    ActiveElevatorCalls.insert(call)
                }
                PersonState[p].waiting.set(true)
            }
            callElevator
            let openElevatorDoors = Do(Step.openElevatorDoors, over: Elevator) { e in
                let car = ElevatorState[e]
                When(!car.doorsOpen && FormalCall(as: Bool.self, "OpenRequested", e))
                ActiveElevatorCalls.remove(Call.expression(floor: car.floor, direction: car.direction))
                ElevatorState[e].buttonsPressed.set(car.buttonsPressed.removing(car.floor))
                ElevatorState[e].doorsOpen.set(true)
            }
            openElevatorDoors
            let enterElevator = Do(Step.enterElevator, over: Elevator) { e in
                let car = ElevatorState[e]
                let gettingOn = FormalCall(as: Set<PersonID>.self, "PeopleWaiting", car.floor, car.direction)
                When(car.doorsOpen && car.direction != "Stationary" && !gettingOn.isEmpty)
                let destinations = gettingOn.mapping { p in PersonState[p].destination }
                ElevatorState[e].buttonsPressed.set(car.buttonsPressed.union(destinations))
                PersonState.set(Dictionary<PersonID, Rider>.mapping(over: Person) { p in
                    If(gettingOn.contains(p), then: Rider.expression(location: Location.second(e),
                        destination: PersonState[p].destination, waiting: PersonState[p].waiting), else: PersonState[p])
                })
            }
            enterElevator
            let exitElevator = Do(Step.exitElevator, over: Elevator) { e in
                let gettingOff = FormalCall(as: Set<PersonID>.self, "GettingOff", e)
                When(ElevatorState[e].doorsOpen && !gettingOff.isEmpty)
                PersonState.set(Dictionary<PersonID, Rider>.mapping(over: Person) { p in
                    If(gettingOff.contains(p), then: Rider.expression(location: Location.first(ElevatorState[e].floor),
                        destination: PersonState[p].destination, waiting: false), else: PersonState[p])
                })
            }
            exitElevator
            let closeElevatorDoors = Do(Step.closeElevatorDoors, over: Elevator) { e in
                When(ElevatorState[e].doorsOpen)
                When(!enterElevator.isEnabled(for: e))
                When(!exitElevator.isEnabled(for: e))
                ElevatorState[e].doorsOpen.set(false)
            }
            closeElevatorDoors
            let moveElevator = Do(Step.moveElevator, over: Elevator) { e in
                let car = ElevatorState[e]
                let next = If(car.direction == "Up", then: car.floor + 1, else: car.floor - 1)
                When(car.direction != "Stationary" && !car.doorsOpen && !car.buttonsPressed.contains(car.floor))
                When(ActiveElevatorCalls.allSatisfy { c in !FormalCall(as: Bool.self, "CanServiceCall", e, c)
                    || Elevator.contains { other in other != e && FormalCall(as: Bool.self, "CanServiceCall", other, c) } })
                When(Floor.contains(next))
                ElevatorState[e].floor.set(next)
            }
            moveElevator
            let stopElevator = Do(Step.stopElevator, over: Elevator) { e in
                let car = ElevatorState[e]
                let next = If(car.direction == "Up", then: car.floor + 1, else: car.floor - 1)
                When(!car.doorsOpen && !openElevatorDoors.isEnabled(for: e) && !Floor.contains(next))
                ElevatorState[e].direction.set("Stationary")
            }
            stopElevator
            let dispatchElevator = Do(Step.dispatchElevator, over: ElevatorCall) { c in
                When(ActiveElevatorCalls.contains(c))
                let stationary = Elevator.filter { e in ElevatorState[e].direction == "Stationary" }
                let approaching = Elevator.filter { e in ElevatorState[e].direction == c.direction
                    && (ElevatorState[e].floor == c.floor || FormalCall(as: String.self, "GetDirection", ElevatorState[e].floor, c.floor) == c.direction) }
                let eligible = stationary.union(approaching)
                When(!eligible.isEmpty)
                let closest = Select(from: eligible) { e in eligible.allSatisfy { other in
                    FormalCall(as: Int.self, "GetDistance", ElevatorState[e].floor, c.floor)
                        <= FormalCall(as: Int.self, "GetDistance", ElevatorState[other].floor, c.floor)
                } }
                If(stationary.contains(closest)) {
                    ElevatorState[closest].floor.set(c.floor)
                    ElevatorState[closest].direction.set(c.direction)
                }
            }
            dispatchElevator

            WeakFairness(each: callElevator)
            WeakFairness(each: openElevatorDoors)
            WeakFairness(each: enterElevator)
            WeakFairness(each: exitElevator)
            StrongFairness(each: closeElevatorDoors)
            StrongFairness(each: moveElevator)
            WeakFairness(each: stopElevator)
            StrongFairness(each: dispatchElevator)

            let TypeInvariant = Invariant()
            TypeInvariant {
                PersonState.keys == Person && ElevatorState.keys == Elevator
                ActiveElevatorCalls.isSubset(of: ElevatorCall)
                Person.allSatisfy { p in Floor.contains(PersonState[p].destination)
                    && (Floor.contains { f in PersonState[p].location == Location.first(f) }
                        || Elevator.contains { e in PersonState[p].location == Location.second(e) }) }
                Elevator.allSatisfy { e in Floor.contains(ElevatorState[e].floor)
                    && Direction.inserting("Stationary").contains(ElevatorState[e].direction)
                    && ElevatorState[e].buttonsPressed.isSubset(of: Floor) }
            }
            let SafetyInvariant = Invariant()
            SafetyInvariant {
                Elevator.allSatisfy { e in ElevatorState[e].buttonsPressed.allSatisfy { f in
                    Person.contains { p in PersonState[p].location == Location.second(e) && PersonState[p].destination == f } } }
                Person.allSatisfy { p in Elevator.allSatisfy { e in PersonState[p].location != Location.second(e)
                    || ElevatorState[e].floor == PersonState[p].destination
                    || ElevatorState[e].direction == FormalCall(as: String.self, "GetDirection", ElevatorState[e].floor, PersonState[p].destination) } }
                ActiveElevatorCalls.allSatisfy { c in !FormalCall(as: Set<PersonID>.self, "PeopleWaiting", c.floor, c.direction).isEmpty }
            }
            let TemporalInvariant = Temporal()
            // Calls use floors 1...FloorCount. Floor zero tags a person's arrival obligation.
            let callSubjects = ElevatorCall.mapping { c in
                LivenessSubject.expression(floor: c.floor, direction: c.direction, person: PersonID.p1)
            }
            let subjects = callSubjects.union(Person.mapping { p in
                LivenessSubject.expression(floor: 0, direction: "", person: p)
            })
            TemporalInvariant(forEach: subjects) { s in
                .conditional(s.floor == 0,
                    then: .leadsTo(PersonState[s.person].waiting,
                        PersonState[s.person].location == Location.first(PersonState[s.person].destination)),
                    else: .leadsTo(ActiveElevatorCalls.contains { c in c.floor == s.floor && c.direction == s.direction },
                        Elevator.contains { e in ElevatorState[e].floor == s.floor && ElevatorState[e].direction == s.direction }))
            }
            Validation("ElevatorLivenessLarge") {
                Bind(Person, to: Set<PersonID>([.p1, .p2]))
                Bind(Elevator, to: Set<CarID>([.e1, .e2]))
                Bind(FloorCount, to: 3)
            }.checking(only: [TypeInvariant, SafetyInvariant, TemporalInvariant])
            Validation("ElevatorLivenessMedium") {
                Bind(Person, to: Set<PersonID>([.p1, .p2]))
                Bind(Elevator, to: Set<CarID>([.e1, .e2]))
                Bind(FloorCount, to: 2)
            }.checking(only: [TypeInvariant, SafetyInvariant, TemporalInvariant])
            Validation("ElevatorSafetyLarge") {
                Bind(Person, to: Set<PersonID>([.p1, .p2, .p3]))
                Bind(Elevator, to: Set<CarID>([.e1, .e2]))
                Bind(FloorCount, to: 5)
            }.checking(only: [TypeInvariant, SafetyInvariant])
            Validation("ElevatorSafetyMedium") {
                Bind(Person, to: Set<PersonID>([.p1, .p2, .p3]))
                Bind(Elevator, to: Set<CarID>([.e1, .e2, .e3]))
                Bind(FloorCount, to: 3)
            }.checking(only: [TypeInvariant, SafetyInvariant])
            Validation("ElevatorSafetySmall") {
                Bind(Person, to: Set<PersonID>([.p1, .p2]))
                Bind(Elevator, to: Set<CarID>([.e1, .e2]))
                Bind(FloorCount, to: 2)
            }.checking(only: [TypeInvariant, SafetyInvariant])
        }
    }
}
