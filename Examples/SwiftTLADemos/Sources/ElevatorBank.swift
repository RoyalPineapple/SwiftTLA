import SwiftTLA
import SwiftTLAMacros

/// A bounded elevator bank whose complete behaviour lives in one formal model.
///
/// There are three floors, two cars, and two riders. Cars move exactly one
/// floor at a time. Doors make boarding and exiting explicit transitions.
/// The generated machine is the only authority for car location, doors, and
/// rider phases; a view renders its typed state.
@TLAModel
public struct ElevatorBank {
    public enum Floor: Int, CaseIterable, FiniteDomainKey {
        case one = 1
        case two = 2
        case three = 3

        public static var defaultValue: Self { .one }
        public static let formalDomain = allCases
        public static let formalTypeIdentity = FormalTypeIdentity(rawValue: "demos.elevator.floor")

        public var tlaValue: TLAValue { .int(rawValue) }
    }

    public enum CarID: String, CaseIterable, FiniteDomainKey {
        case carA
        case carB

        public static var defaultValue: Self { .carA }
        public static let formalDomain = allCases
        public static let formalTypeIdentity = FormalTypeIdentity(rawValue: "demos.elevator.car")

        public var tlaValue: TLAValue { .string(rawValue) }
    }

    /// `none` is a formal sentinel for an empty car. It is deliberately part
    /// of the finite rider domain so the car record stays total and typed.
    public enum Rider: String, CaseIterable, FiniteDomainKey {
        case none
        case alice
        case bob

        public static var defaultValue: Self { .none }
        public static let formalDomain = allCases
        public static let formalTypeIdentity = FormalTypeIdentity(rawValue: "demos.elevator.rider")

        public var tlaValue: TLAValue { .string(rawValue) }
    }

    public enum Door: String, CaseIterable, FiniteDomainKey {
        case closed
        case open

        public static var defaultValue: Self { .closed }
        public static let formalDomain = allCases
        public static let formalTypeIdentity = FormalTypeIdentity(rawValue: "demos.elevator.door")

        public var tlaValue: TLAValue { .string(rawValue) }
    }

    public enum RiderPhase: String, CaseIterable, FiniteDomainKey {
        case waiting
        case onboard
        case arrived

        public static var defaultValue: Self { .waiting }
        public static let formalDomain = allCases
        public static let formalTypeIdentity = FormalTypeIdentity(rawValue: "demos.elevator.rider-phase")

        public var tlaValue: TLAValue { .string(rawValue) }
    }

    private enum Step: String, PlusCalLabel, CaseIterable {
        case operate
    }

    public struct CarFields {
        public let floor: Floor
        public let door: Door
        public let rider: Rider
    }

    public enum CarSchema: TLARecordSchema {
        public typealias Fields = CarFields

        public static let fieldNames: Set<String> = ["floor", "door", "rider"]
        public static let defaultRecord: TLAValue = .record([
            "floor": .int(Floor.one.rawValue),
            "door": .string(Door.closed.rawValue),
            "rider": .string(Rider.none.rawValue)
        ])

        public static func fieldName<Value>(for field: KeyPath<CarFields, Value>) -> String? {
            let key = field as AnyKeyPath
            if key == \CarFields.floor { return "floor" }
            if key == \CarFields.door { return "door" }
            if key == \CarFields.rider { return "rider" }
            return nil
        }

        public static let floor = field(\CarFields.floor)
        public static let door = field(\CarFields.door)
        public static let rider = field(\CarFields.rider)
    }

    public struct RiderFields {
        public let phase: RiderPhase
        public let floor: Floor
        public let destination: Floor
    }

    public enum RiderSchema: TLARecordSchema {
        public typealias Fields = RiderFields

        public static let fieldNames: Set<String> = ["phase", "floor", "destination"]
        public static let defaultRecord: TLAValue = .record([
            "phase": .string(RiderPhase.arrived.rawValue),
            "floor": .int(Floor.one.rawValue),
            "destination": .int(Floor.one.rawValue)
        ])

        public static func fieldName<Value>(for field: KeyPath<RiderFields, Value>) -> String? {
            let key = field as AnyKeyPath
            if key == \RiderFields.phase { return "phase" }
            if key == \RiderFields.floor { return "floor" }
            if key == \RiderFields.destination { return "destination" }
            return nil
        }

        public static let phase = field(\RiderFields.phase)
        public static let floor = field(\RiderFields.floor)
        public static let destination = field(\RiderFields.destination)
    }

    public static var spec: TLASpec {
        #spec("ElevatorBank") {
            Algorithm("ElevatorBank") { scope in
                let cars = scope.sharedVar("cars", initial: Function<CarID, Record<CarSchema>>.literal(
                    (.carA, Record.literal(.init(CarSchema.floor, .one), .init(CarSchema.door, .closed), .init(CarSchema.rider, .none))),
                    (.carB, Record.literal(.init(CarSchema.floor, .three), .init(CarSchema.door, .closed), .init(CarSchema.rider, .none)))
                ))
                let riders = scope.sharedVar("riders", initial: Function<Rider, Record<RiderSchema>>.literal(
                    (.none, Record.literal(.init(RiderSchema.phase, .arrived), .init(RiderSchema.floor, .one), .init(RiderSchema.destination, .one))),
                    (.alice, Record.literal(.init(RiderSchema.phase, .waiting), .init(RiderSchema.floor, .one), .init(RiderSchema.destination, .three))),
                    (.bob, Record.literal(.init(RiderSchema.phase, .waiting), .init(RiderSchema.floor, .three), .init(RiderSchema.destination, .one)))
                ))

                Each(CarID.all, fairness: .weak) { car in
                    Do(Step.operate) {
                        Either {
                            With(Rider.all) { rider in
                                When(cars[car][CarSchema.door] == .closed)
                                When(cars[car][CarSchema.rider] == .none)
                                When(riders[rider][RiderSchema.phase] == .waiting)
                                When(riders[rider][RiderSchema.floor] == cars[car][CarSchema.floor])
                                Assign(cars, to: cars.updating(car) { vehicle in
                                    vehicle.updating(CarSchema.door, to: .open)
                                })
                            }
                        } or: {
                            Either {
                            With(Rider.all) { rider in
                                When(cars[car][CarSchema.door] == .open)
                                When(cars[car][CarSchema.rider] == .none)
                                When(riders[rider][RiderSchema.phase] == .waiting)
                                When(riders[rider][RiderSchema.floor] == cars[car][CarSchema.floor])
                                Assign(cars, to: cars.updating(car) { vehicle in
                                    vehicle
                                        .updating(CarSchema.rider, to: rider)
                                        .updating(CarSchema.door, to: .closed)
                                })
                                Assign(riders, to: riders.updating(rider) { passenger in
                                    passenger.updating(RiderSchema.phase, to: .onboard)
                                })
                            }
                            } or: {
                                Either {
                            When(cars[car][CarSchema.door] == .closed)
                            When(cars[car][CarSchema.rider] != .none)
                            When(cars[car][CarSchema.floor] < riders[cars[car][CarSchema.rider]][RiderSchema.destination])
                            Either {
                                When(cars[car][CarSchema.floor] == .one)
                                Assign(cars, to: cars.updating(car) { vehicle in
                                    vehicle.updating(CarSchema.floor, to: .two)
                                })
                            } or: {
                                When(cars[car][CarSchema.floor] == .two)
                                Assign(cars, to: cars.updating(car) { vehicle in
                                    vehicle.updating(CarSchema.floor, to: .three)
                                })
                            }
                                } or: {
                                    Either {
                            When(cars[car][CarSchema.door] == .closed)
                            When(cars[car][CarSchema.rider] != .none)
                            When(cars[car][CarSchema.floor] > riders[cars[car][CarSchema.rider]][RiderSchema.destination])
                            Either {
                                When(cars[car][CarSchema.floor] == .three)
                                Assign(cars, to: cars.updating(car) { vehicle in
                                    vehicle.updating(CarSchema.floor, to: .two)
                                })
                            } or: {
                                When(cars[car][CarSchema.floor] == .two)
                                Assign(cars, to: cars.updating(car) { vehicle in
                                    vehicle.updating(CarSchema.floor, to: .one)
                                })
                            }
                                    } or: {
                                        Either {
                            When(cars[car][CarSchema.door] == .closed)
                            When(cars[car][CarSchema.rider] != .none)
                            When(cars[car][CarSchema.floor] == riders[cars[car][CarSchema.rider]][RiderSchema.destination])
                            Assign(cars, to: cars.updating(car) { vehicle in
                                vehicle.updating(CarSchema.door, to: .open)
                            })
                                        } or: {
                                            Either {
                            When(cars[car][CarSchema.door] == .open)
                            When(cars[car][CarSchema.rider] != .none)
                            When(riders[cars[car][CarSchema.rider]][RiderSchema.phase] == .onboard)
                            When(cars[car][CarSchema.floor] == riders[cars[car][CarSchema.rider]][RiderSchema.destination])
                            Assign(cars, to: cars.updating(car) { vehicle in
                                vehicle.updating(CarSchema.rider, to: .none)
                            })
                            Assign(riders, to: riders.updating(cars[car][CarSchema.rider]) { passenger in
                                passenger.updating(RiderSchema.phase, to: .arrived)
                            })
                                            } or: {
                            When(cars[car][CarSchema.door] == .open)
                            When(cars[car][CarSchema.rider] == .none)
                            Assign(cars, to: cars.updating(car) { vehicle in
                                vehicle.updating(CarSchema.door, to: .closed)
                            })
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        Goto(Step.operate)
                    }
                }

                Invariant("CarFloorDomain") {
                    cars[.carA][CarSchema.floor] == .one
                        || cars[.carA][CarSchema.floor] == .two
                        || cars[.carA][CarSchema.floor] == .three
                    cars[.carB][CarSchema.floor] == .one
                        || cars[.carB][CarSchema.floor] == .two
                        || cars[.carB][CarSchema.floor] == .three
                }
            }
        }
    }

    @TLAObservable
    public final class Observable {}
}
