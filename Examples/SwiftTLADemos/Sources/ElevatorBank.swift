import SwiftTLA
import SwiftTLAMacros

/// A bounded elevator bank whose complete behaviour lives in one typed source model.
///
/// There are three floors, two cars, and two riders. Cars move exactly one
/// floor at a time. Doors make boarding and exiting explicit transitions.
/// The generated machine is the only authority for car location, doors, and
/// rider phases; a view renders its typed state.
@TLAModel
public struct ElevatorBank {
    public enum Floor: Int, CaseIterable {
        case one = 1, two = 2, three = 3
    }

    public enum CarID: String, CaseIterable {
        case carA, carB
    }

    /// `none` represents an empty car and remains part of the total rider domain.
    public enum Rider: String, CaseIterable {
        case none, alice, bob
    }

    public enum Door: String, CaseIterable {
        case closed, open
    }

    public enum RiderPhase: String, CaseIterable {
        case waiting, onboard, arrived
    }

    private enum Step: String, CaseIterable {
        case operate
    }

    public struct Car: Hashable, Sendable {
        public let floor: Floor
        public let door: Door
        public let rider: Rider
    }

    public struct Passenger: Hashable, Sendable {
        public let phase: RiderPhase
        public let floor: Floor
        public let destination: Floor
    }

    public static var spec: TLASpec {
        #spec("ElevatorBank") { scope in
            let cars: SharedVariable<[CarID: Car]> = scope.sharedVar(initial: [
                .carA: Car(floor: .one, door: .closed, rider: .none),
                .carB: Car(floor: .three, door: .closed, rider: .none)
            ])
            let riders: SharedVariable<[Rider: Passenger]> = scope.sharedVar(initial: [
                .none: Passenger(phase: .arrived, floor: .one, destination: .one),
                .alice: Passenger(phase: .waiting, floor: .one, destination: .three),
                .bob: Passenger(phase: .waiting, floor: .three, destination: .one)
            ])
            let CarFloorDomain = Invariant()

            Algorithm("ElevatorBank") {
                Each(CarID.all, fairness: .weak) { car in
                    Do(Step.operate) {
                        Either {
                            With(Rider.all) { rider in
                                When(cars[car].door == .closed)
                                When(cars[car].rider == .none)
                                When(riders[rider].phase == .waiting)
                                When(riders[rider].floor == cars[car].floor)
                                Assign(cars[car].door, to: .open)
                            }
                        } or: {
                            Either {
                                With(Rider.all) { rider in
                                    When(cars[car].door == .open)
                                    When(cars[car].rider == .none)
                                    When(riders[rider].phase == .waiting)
                                    When(riders[rider].floor == cars[car].floor)
                                    Assign(cars[car].rider, to: rider)
                                    Assign(cars[car].door, to: .closed)
                                    Assign(riders[rider].phase, to: .onboard)
                                }
                            } or: {
                                Either {
                                    When(cars[car].door == .closed)
                                    When(cars[car].rider != .none)
                                    When(cars[car].floor < riders[cars[car].rider].destination)
                                    Either {
                                        When(cars[car].floor == .one)
                                        Assign(cars[car].floor, to: .two)
                                    } or: {
                                        When(cars[car].floor == .two)
                                        Assign(cars[car].floor, to: .three)
                                    }
                                } or: {
                                    Either {
                                        When(cars[car].door == .closed)
                                        When(cars[car].rider != .none)
                                        When(cars[car].floor > riders[cars[car].rider].destination)
                                        Either {
                                            When(cars[car].floor == .three)
                                            Assign(cars[car].floor, to: .two)
                                        } or: {
                                            When(cars[car].floor == .two)
                                            Assign(cars[car].floor, to: .one)
                                        }
                                    } or: {
                                        Either {
                                            When(cars[car].door == .closed)
                                            When(cars[car].rider != .none)
                                            When(cars[car].floor == riders[cars[car].rider].destination)
                                            Assign(cars[car].door, to: .open)
                                        } or: {
                                            When(cars[car].door == .open)
                                            When(cars[car].rider != .none)
                                            When(riders[cars[car].rider].phase == .onboard)
                                            When(cars[car].floor == riders[cars[car].rider].destination)
                                            let exitingRider = cars[car].rider
                                            Assign(cars[car].rider, to: .none)
                                            Assign(cars[car].door, to: .closed)
                                            Assign(riders[exitingRider].phase, to: .arrived)
                                        }
                                    }
                                }
                            }
                        }
                        Goto(Step.operate)
                    }
                }
            }

            CarFloorDomain {
                cars[.carA].floor == .one || cars[.carA].floor == .two || cars[.carA].floor == .three
                cars[.carB].floor == .one || cars[.carB].floor == .two || cars[.carB].floor == .three
            }
        }
    }
}
