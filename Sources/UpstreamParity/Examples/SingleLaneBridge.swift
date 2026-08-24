import SwiftTLA
import SwiftTLAMacros

@TLAModel
public struct SingleLaneBridgeModel: Sendable {
    public enum Car: String, CaseIterable, FiniteDomainKey {
        case rightOne = "r1"
        case rightTwo = "r2"
        case leftOne = "l1"
        case leftTwo = "l2"

        public static var defaultValue: Self { .rightOne }
        public static let formalDomain = allCases
        public static let formalTypeIdentity = FormalTypeIdentity(rawValue: "upstream.single-lane-bridge.car")

        public var tlaValue: TLAValue { .string(rawValue) }
    }

    public static var spec: TLASpec {
        #spec("SingleLaneBridge") {
            Extends(.naturals, .sequences)
            Constant("CarsRight", SetExpr<Car>(.rightOne, .rightTwo))
            Constant("CarsLeft", SetExpr<Car>(.leftOne, .leftTwo))
            Constant("Bridge", SetExpr<Int>(4, 5))
            Constant("Positions", SetExpr<Int>(1, 2, 3, 4, 5, 6, 7, 8))

            FormalDefinition("IsRight", taking: Car.self) { car in
                SetExpr<Car>.literal(.rightOne, .rightTwo).contains(car)
            }
            FormalDefinition("InBridge", taking: Int.self) { position in
                SetExpr<Int>.literal(4, 5).contains(position)
            }
            FormalDefinition("NextLocation", taking: Car.self, Int.self) { car, position in
                If(
                    FormalCall(as: Bool.self, "IsRight", car),
                    then: If(position > 1, then: position - 1, else: 8),
                    else: If(position < 8, then: position + 1, else: 1)
                )
            }
            FormalDefinition("LocationAt", taking: Function<Car, Int>.self, Car.self) { locations, car in
                locations[car]
            }
            FormalDefinition("CarsOnBridge", taking: Function<Car, Int>.self) { locations in
                SetExpr<Car>.literal(.rightOne, .rightTwo, .leftOne, .leftTwo).filtering { car in
                    FormalCall(as: Bool.self, "InBridge", locations[car])
                }
            }

            let location = Var<Function<Car, Int>>("Location")
            let waiting = Var<TupleExpr<Car>>("WaitingBeforeBridge")
            Variable(computed: location) {
                Function<Car, Int>.literal(
                (.rightOne, 8),
                (.rightTwo, 8),
                (.leftOne, 1),
                (.leftTwo, 1)
                )
            }
            Variable(waiting, TupleExpr<Car>())

            Invariant("Invariants") {
                let allCars = SetExpr<Car>.literal(.rightOne, .rightTwo, .leftOne, .leftTwo)
                let carsOnBridge: Expr<SetExpr<Car>> = FormalCall("CarsOnBridge", location)
                All(in: allCars, and: allCars) { first, second in
                    first == second
                        || !(FormalCall(
                            as: Bool.self,
                            "InBridge",
                            FormalCall(as: Int.self, "LocationAt", location, first.expr)
                        ) && FormalCall(as: Int.self, "LocationAt", location, first.expr)
                            == FormalCall(as: Int.self, "LocationAt", location, second.expr))
                }
                carsOnBridge.cardinality < 3
                All(
                    in: SetExpr<Car>.literal(.rightOne, .rightTwo),
                    and: SetExpr<Car>.literal(.leftOne, .leftTwo)
                ) { right, left in
                    !(FormalCall(
                        as: Bool.self,
                        "InBridge",
                        FormalCall(as: Int.self, "LocationAt", location, right.expr)
                    ) && FormalCall(
                        as: Bool.self,
                        "InBridge",
                        FormalCall(as: Int.self, "LocationAt", location, left.expr)
                    ))
                }
            }

            Action("MoveOutside_r1") {
                let next: Expr<Int> = FormalCall("NextLocation", Car.rightOne, location[.rightOne])
                let leaving = FormalCall(as: Bool.self, "IsRight", Car.rightOne) && next == 6
                    || !FormalCall(as: Bool.self, "IsRight", Car.rightOne) && next == 3
                !FormalCall(as: Bool.self, "InBridge", next) && next != location[.rightOne]
                (location.becomes(location.updating(.rightOne, to: next))
                    && waiting.becomes(Expr<TupleExpr<Car>>(waiting.appending(Car.rightOne.stateExpr)))
                ).when(leaving)
                    || (location.becomes(location.updating(.rightOne, to: next)) && waiting.stays).when(!leaving)
            }
            Action("MoveInside_r1") {
                let next: Expr<Int> = FormalCall("NextLocation", Car.rightOne, location[.rightOne])
                let carsOnBridge: Expr<SetExpr<Car>> = FormalCall("CarsOnBridge", location)
                let leaving = FormalCall(as: Bool.self, "IsRight", Car.rightOne) && next == 6
                    || !FormalCall(as: Bool.self, "IsRight", Car.rightOne) && next == 3
                carsOnBridge.contains(.rightOne)
                    && All(in: SetExpr<Car>.literal(.rightOne, .rightTwo, .leftOne, .leftTwo)) { car in
                        FormalCall(as: Int.self, "LocationAt", location, car.expr) != next
                    }
                (location.becomes(location.updating(.rightOne, to: next))
                    && waiting.becomes(Expr<TupleExpr<Car>>(waiting.appending(Car.rightOne.stateExpr)))
                ).when(leaving)
                    || (location.becomes(location.updating(.rightOne, to: next)) && waiting.stays).when(!leaving)
            }
            Action("Enter_r1") {
                let next: Expr<Int> = FormalCall("NextLocation", Car.rightOne, location[.rightOne])
                let carsOnBridge: Expr<SetExpr<Car>> = FormalCall("CarsOnBridge", location)
                let head = Expr<Car>(waiting.head)
                waiting.count > 0 && head == Car.rightOne
                carsOnBridge.isEmpty
                    || (!carsOnBridge.contains(head)
                        && All(in: carsOnBridge) { car in
                            FormalCall(as: Bool.self, "IsRight", car.expr)
                                == FormalCall(as: Bool.self, "IsRight", Car.rightOne)
                        }
                        && All(in: SetExpr<Car>.literal(.rightOne, .rightTwo, .leftOne, .leftTwo)) { car in
                            FormalCall(as: Int.self, "LocationAt", location, car.expr) != next
                        })
                location.becomes(location.updating(.rightOne, to: next))
                waiting.becomes(Expr<TupleExpr<Car>>(waiting.tail))
            }

            Action("MoveOutside_r2") {
                let next: Expr<Int> = FormalCall("NextLocation", Car.rightTwo, location[.rightTwo])
                let leaving = FormalCall(as: Bool.self, "IsRight", Car.rightTwo) && next == 6
                    || !FormalCall(as: Bool.self, "IsRight", Car.rightTwo) && next == 3
                !FormalCall(as: Bool.self, "InBridge", next) && next != location[.rightTwo]
                (location.becomes(location.updating(.rightTwo, to: next))
                    && waiting.becomes(Expr<TupleExpr<Car>>(waiting.appending(Car.rightTwo.stateExpr)))
                ).when(leaving)
                    || (location.becomes(location.updating(.rightTwo, to: next)) && waiting.stays).when(!leaving)
            }
            Action("MoveInside_r2") {
                let next: Expr<Int> = FormalCall("NextLocation", Car.rightTwo, location[.rightTwo])
                let carsOnBridge: Expr<SetExpr<Car>> = FormalCall("CarsOnBridge", location)
                let leaving = FormalCall(as: Bool.self, "IsRight", Car.rightTwo) && next == 6
                    || !FormalCall(as: Bool.self, "IsRight", Car.rightTwo) && next == 3
                carsOnBridge.contains(.rightTwo)
                    && All(in: SetExpr<Car>.literal(.rightOne, .rightTwo, .leftOne, .leftTwo)) { car in
                        FormalCall(as: Int.self, "LocationAt", location, car.expr) != next
                    }
                (location.becomes(location.updating(.rightTwo, to: next))
                    && waiting.becomes(Expr<TupleExpr<Car>>(waiting.appending(Car.rightTwo.stateExpr)))
                ).when(leaving)
                    || (location.becomes(location.updating(.rightTwo, to: next)) && waiting.stays).when(!leaving)
            }
            Action("Enter_r2") {
                let next: Expr<Int> = FormalCall("NextLocation", Car.rightTwo, location[.rightTwo])
                let carsOnBridge: Expr<SetExpr<Car>> = FormalCall("CarsOnBridge", location)
                let head = Expr<Car>(waiting.head)
                waiting.count > 0 && head == Car.rightTwo
                carsOnBridge.isEmpty
                    || (!carsOnBridge.contains(head)
                        && All(in: carsOnBridge) { car in
                            FormalCall(as: Bool.self, "IsRight", car.expr)
                                == FormalCall(as: Bool.self, "IsRight", Car.rightTwo)
                        }
                        && All(in: SetExpr<Car>.literal(.rightOne, .rightTwo, .leftOne, .leftTwo)) { car in
                            FormalCall(as: Int.self, "LocationAt", location, car.expr) != next
                        })
                location.becomes(location.updating(.rightTwo, to: next))
                waiting.becomes(Expr<TupleExpr<Car>>(waiting.tail))
            }

            Action("MoveOutside_l1") {
                let next: Expr<Int> = FormalCall("NextLocation", Car.leftOne, location[.leftOne])
                let leaving = FormalCall(as: Bool.self, "IsRight", Car.leftOne) && next == 6
                    || !FormalCall(as: Bool.self, "IsRight", Car.leftOne) && next == 3
                !FormalCall(as: Bool.self, "InBridge", next) && next != location[.leftOne]
                (location.becomes(location.updating(.leftOne, to: next))
                    && waiting.becomes(Expr<TupleExpr<Car>>(waiting.appending(Car.leftOne.stateExpr)))
                ).when(leaving)
                    || (location.becomes(location.updating(.leftOne, to: next)) && waiting.stays).when(!leaving)
            }
            Action("MoveInside_l1") {
                let next: Expr<Int> = FormalCall("NextLocation", Car.leftOne, location[.leftOne])
                let carsOnBridge: Expr<SetExpr<Car>> = FormalCall("CarsOnBridge", location)
                let leaving = FormalCall(as: Bool.self, "IsRight", Car.leftOne) && next == 6
                    || !FormalCall(as: Bool.self, "IsRight", Car.leftOne) && next == 3
                carsOnBridge.contains(.leftOne)
                    && All(in: SetExpr<Car>.literal(.rightOne, .rightTwo, .leftOne, .leftTwo)) { car in
                        FormalCall(as: Int.self, "LocationAt", location, car.expr) != next
                    }
                (location.becomes(location.updating(.leftOne, to: next))
                    && waiting.becomes(Expr<TupleExpr<Car>>(waiting.appending(Car.leftOne.stateExpr)))
                ).when(leaving)
                    || (location.becomes(location.updating(.leftOne, to: next)) && waiting.stays).when(!leaving)
            }
            Action("Enter_l1") {
                let next: Expr<Int> = FormalCall("NextLocation", Car.leftOne, location[.leftOne])
                let carsOnBridge: Expr<SetExpr<Car>> = FormalCall("CarsOnBridge", location)
                let head = Expr<Car>(waiting.head)
                waiting.count > 0 && head == Car.leftOne
                carsOnBridge.isEmpty
                    || (!carsOnBridge.contains(head)
                        && All(in: carsOnBridge) { car in
                            FormalCall(as: Bool.self, "IsRight", car.expr)
                                == FormalCall(as: Bool.self, "IsRight", Car.leftOne)
                        }
                        && All(in: SetExpr<Car>.literal(.rightOne, .rightTwo, .leftOne, .leftTwo)) { car in
                            FormalCall(as: Int.self, "LocationAt", location, car.expr) != next
                        })
                location.becomes(location.updating(.leftOne, to: next))
                waiting.becomes(Expr<TupleExpr<Car>>(waiting.tail))
            }

            Action("MoveOutside_l2") {
                let next: Expr<Int> = FormalCall("NextLocation", Car.leftTwo, location[.leftTwo])
                let leaving = FormalCall(as: Bool.self, "IsRight", Car.leftTwo) && next == 6
                    || !FormalCall(as: Bool.self, "IsRight", Car.leftTwo) && next == 3
                !FormalCall(as: Bool.self, "InBridge", next) && next != location[.leftTwo]
                (location.becomes(location.updating(.leftTwo, to: next))
                    && waiting.becomes(Expr<TupleExpr<Car>>(waiting.appending(Car.leftTwo.stateExpr)))
                ).when(leaving)
                    || (location.becomes(location.updating(.leftTwo, to: next)) && waiting.stays).when(!leaving)
            }
            Action("MoveInside_l2") {
                let next: Expr<Int> = FormalCall("NextLocation", Car.leftTwo, location[.leftTwo])
                let carsOnBridge: Expr<SetExpr<Car>> = FormalCall("CarsOnBridge", location)
                let leaving = FormalCall(as: Bool.self, "IsRight", Car.leftTwo) && next == 6
                    || !FormalCall(as: Bool.self, "IsRight", Car.leftTwo) && next == 3
                carsOnBridge.contains(.leftTwo)
                    && All(in: SetExpr<Car>.literal(.rightOne, .rightTwo, .leftOne, .leftTwo)) { car in
                        FormalCall(as: Int.self, "LocationAt", location, car.expr) != next
                    }
                (location.becomes(location.updating(.leftTwo, to: next))
                    && waiting.becomes(Expr<TupleExpr<Car>>(waiting.appending(Car.leftTwo.stateExpr)))
                ).when(leaving)
                    || (location.becomes(location.updating(.leftTwo, to: next)) && waiting.stays).when(!leaving)
            }
            Action("Enter_l2") {
                let next: Expr<Int> = FormalCall("NextLocation", Car.leftTwo, location[.leftTwo])
                let carsOnBridge: Expr<SetExpr<Car>> = FormalCall("CarsOnBridge", location)
                let head = Expr<Car>(waiting.head)
                waiting.count > 0 && head == Car.leftTwo
                carsOnBridge.isEmpty
                    || (!carsOnBridge.contains(head)
                        && All(in: carsOnBridge) { car in
                            FormalCall(as: Bool.self, "IsRight", car.expr)
                                == FormalCall(as: Bool.self, "IsRight", Car.leftTwo)
                        }
                        && All(in: SetExpr<Car>.literal(.rightOne, .rightTwo, .leftOne, .leftTwo)) { car in
                            FormalCall(as: Int.self, "LocationAt", location, car.expr) != next
                        })
                location.becomes(location.updating(.leftTwo, to: next))
                waiting.becomes(Expr<TupleExpr<Car>>(waiting.tail))
            }
        }
    }
}

extension Example {
    static let singleLaneBridge = Example.Entry(
        id: "SingleLaneBridge/MC",
        upstreamSpec: "SingleLaneBridge",
        upstreamModule: "specifications/SingleLaneBridge/SingleLaneBridge.tla",
        upstreamCfg: "specifications/SingleLaneBridge/MC.cfg",
        expectedDistinct: 3605,
        spec: SingleLaneBridgeModel.spec,
        notes: "2R+2L, bridge {4,5}. Typed finite domains and direct actions. 3605 states.",
    )
}
