import SwiftTLA
import SwiftTLAMacros

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
                    FormalCall("IsRight", car) == true,
                    then: If(position > 1, then: Expr<Int>(position - 1), else: Expr<Int>(8)),
                    else: If(position < 8, then: Expr<Int>(position + 1), else: Expr<Int>(1))
                )
            }
            FormalDefinition("LocationAt", taking: Function<Car, Int>.self, Car.self) { locations, car in
                locations[car]
            }
            FormalDefinition("CarsOnBridge", taking: Function<Car, Int>.self) { locations in
                SetExpr<Car>.literal(.rightOne, .rightTwo, .leftOne, .leftTwo).filtering { car in
                    FormalCall(as: Bool.self, "InBridge", locations[car]).raw
                }
            }
            FormalDefinition("IsLeaving", taking: Car.self, Function<Car, Int>.self) { car, locations in
                FormalCall(as: Bool.self, "IsRight", car)
                    && FormalCall(as: Int.self, "NextLocation", car, locations[car]) == 6
                    || !FormalCall(as: Bool.self, "IsRight", car)
                    && FormalCall(as: Int.self, "NextLocation", car, locations[car]) == 3
            }

            let location = Var<Function<Car, Int>>("Location")
            let waiting = Var<TupleExpr<Car>>("WaitingBeforeBridge")
            Variable(computed: location) {
                Function<Car, Int>.literal(
                (.rightOne, 8),
                (.rightTwo, 8),
                (.leftOne, 1),
                (.leftTwo, 1)
                ).raw
            }
            Variable(computed: waiting) { Expr<TupleExpr<Car>>(TupleExpr<Car>()).raw }

            Invariant("Invariants") {
                All(in: SetExpr<Car>.literal(.rightOne, .rightTwo, .leftOne, .leftTwo)) { first in
                    All(in: SetExpr<Car>.literal(.rightOne, .rightTwo, .leftOne, .leftTwo)) { second in
                        first == second
                            || !(FormalCall(
                                as: Bool.self,
                                "InBridge",
                                FormalCall(as: Int.self, "LocationAt", location, first.expr)
                            ) && FormalCall(as: Int.self, "LocationAt", location, first.expr)
                                == FormalCall(as: Int.self, "LocationAt", location, second.expr))
                    }
                }
                FormalCall(as: SetExpr<Car>.self, "CarsOnBridge", location).cardinality < 3
                All(in: SetExpr<Car>.literal(.rightOne, .rightTwo)) { right in
                    All(in: SetExpr<Car>.literal(.leftOne, .leftTwo)) { left in
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
            }

            Action("MoveOutside_r1") {
                !FormalCall(
                    as: Bool.self,
                    "InBridge",
                    FormalCall(as: Int.self, "NextLocation", Car.rightOne, location[.rightOne])
                ) && FormalCall(as: Int.self, "NextLocation", Car.rightOne, location[.rightOne]) != location[.rightOne]
                (location.becomes(location.updating(
                    .rightOne,
                    to: FormalCall(as: Int.self, "NextLocation", Car.rightOne, location[.rightOne])
                ))
                    && waiting.becomes(Expr<TupleExpr<Car>>(waiting.stateExpr).appending(Car.rightOne))
                ).when(FormalCall(as: Bool.self, "IsLeaving", Car.rightOne, location))
                    || (location.becomes(location.updating(
                        .rightOne,
                        to: FormalCall(as: Int.self, "NextLocation", Car.rightOne, location[.rightOne])
                    )) && waiting.stays).when(!FormalCall(as: Bool.self, "IsLeaving", Car.rightOne, location))
            }
            Action("MoveInside_r1") {
                FormalCall(as: SetExpr<Car>.self, "CarsOnBridge", location).contains(.rightOne)
                    && All(in: SetExpr<Car>.literal(.rightOne, .rightTwo, .leftOne, .leftTwo)) { car in
                        FormalCall(as: Int.self, "LocationAt", location, car.expr)
                            != FormalCall(as: Int.self, "NextLocation", Car.rightOne, location[.rightOne])
                    }
                (location.becomes(location.updating(
                    .rightOne,
                    to: FormalCall(as: Int.self, "NextLocation", Car.rightOne, location[.rightOne])
                ))
                    && waiting.becomes(Expr<TupleExpr<Car>>(waiting.stateExpr).appending(Car.rightOne))
                ).when(FormalCall(as: Bool.self, "IsLeaving", Car.rightOne, location))
                    || (location.becomes(location.updating(
                        .rightOne,
                        to: FormalCall(as: Int.self, "NextLocation", Car.rightOne, location[.rightOne])
                    )) && waiting.stays).when(!FormalCall(as: Bool.self, "IsLeaving", Car.rightOne, location))
            }
            Action("Enter_r1") {
                let waitingQueue = Expr<TupleExpr<Car>>(waiting.stateExpr)
                let nextCar = Expr<Car>(.tupleHead(waiting.stateExpr))
                waitingQueue.count > 0 && nextCar == Car.rightOne
                FormalCall(as: SetExpr<Car>.self, "CarsOnBridge", location).isEmpty
                    || (!FormalCall(as: SetExpr<Car>.self, "CarsOnBridge", location).contains(nextCar)
                        && All(in: FormalCall(as: SetExpr<Car>.self, "CarsOnBridge", location)) { car in
                            FormalCall(as: Bool.self, "IsRight", car.expr)
                                == FormalCall(as: Bool.self, "IsRight", Car.rightOne)
                        }
                        && All(in: SetExpr<Car>.literal(.rightOne, .rightTwo, .leftOne, .leftTwo)) { car in
                            FormalCall(as: Int.self, "LocationAt", location, car.expr)
                                != FormalCall(as: Int.self, "NextLocation", Car.rightOne, location[.rightOne])
                        })
                location.becomes(location.updating(
                    .rightOne,
                    to: FormalCall(as: Int.self, "NextLocation", Car.rightOne, location[.rightOne])
                ))
                waiting.becomes(Expr<TupleExpr<Car>>(waiting.tail))
            }

            Action("MoveOutside_r2") {
                !FormalCall(
                    as: Bool.self,
                    "InBridge",
                    FormalCall(as: Int.self, "NextLocation", Car.rightTwo, location[.rightTwo])
                ) && FormalCall(as: Int.self, "NextLocation", Car.rightTwo, location[.rightTwo]) != location[.rightTwo]
                (location.becomes(location.updating(
                    .rightTwo,
                    to: FormalCall(as: Int.self, "NextLocation", Car.rightTwo, location[.rightTwo])
                ))
                    && waiting.becomes(Expr<TupleExpr<Car>>(waiting.stateExpr).appending(Car.rightTwo))
                ).when(FormalCall(as: Bool.self, "IsLeaving", Car.rightTwo, location))
                    || (location.becomes(location.updating(
                        .rightTwo,
                        to: FormalCall(as: Int.self, "NextLocation", Car.rightTwo, location[.rightTwo])
                    )) && waiting.stays).when(!FormalCall(as: Bool.self, "IsLeaving", Car.rightTwo, location))
            }
            Action("MoveInside_r2") {
                FormalCall(as: SetExpr<Car>.self, "CarsOnBridge", location).contains(.rightTwo)
                    && All(in: SetExpr<Car>.literal(.rightOne, .rightTwo, .leftOne, .leftTwo)) { car in
                        FormalCall(as: Int.self, "LocationAt", location, car.expr)
                            != FormalCall(as: Int.self, "NextLocation", Car.rightTwo, location[.rightTwo])
                    }
                (location.becomes(location.updating(
                    .rightTwo,
                    to: FormalCall(as: Int.self, "NextLocation", Car.rightTwo, location[.rightTwo])
                ))
                    && waiting.becomes(Expr<TupleExpr<Car>>(waiting.stateExpr).appending(Car.rightTwo))
                ).when(FormalCall(as: Bool.self, "IsLeaving", Car.rightTwo, location))
                    || (location.becomes(location.updating(
                        .rightTwo,
                        to: FormalCall(as: Int.self, "NextLocation", Car.rightTwo, location[.rightTwo])
                    )) && waiting.stays).when(!FormalCall(as: Bool.self, "IsLeaving", Car.rightTwo, location))
            }
            Action("Enter_r2") {
                let waitingQueue = Expr<TupleExpr<Car>>(waiting.stateExpr)
                let nextCar = Expr<Car>(.tupleHead(waiting.stateExpr))
                waitingQueue.count > 0 && nextCar == Car.rightTwo
                FormalCall(as: SetExpr<Car>.self, "CarsOnBridge", location).isEmpty
                    || (!FormalCall(as: SetExpr<Car>.self, "CarsOnBridge", location).contains(nextCar)
                        && All(in: FormalCall(as: SetExpr<Car>.self, "CarsOnBridge", location)) { car in
                            FormalCall(as: Bool.self, "IsRight", car.expr)
                                == FormalCall(as: Bool.self, "IsRight", Car.rightTwo)
                        }
                        && All(in: SetExpr<Car>.literal(.rightOne, .rightTwo, .leftOne, .leftTwo)) { car in
                            FormalCall(as: Int.self, "LocationAt", location, car.expr)
                                != FormalCall(as: Int.self, "NextLocation", Car.rightTwo, location[.rightTwo])
                        })
                location.becomes(location.updating(
                    .rightTwo,
                    to: FormalCall(as: Int.self, "NextLocation", Car.rightTwo, location[.rightTwo])
                ))
                waiting.becomes(Expr<TupleExpr<Car>>(waiting.tail))
            }

            Action("MoveOutside_l1") {
                !FormalCall(as: Bool.self, "InBridge", FormalCall(as: Int.self, "NextLocation", Car.leftOne, location[.leftOne]))
                    && FormalCall(as: Int.self, "NextLocation", Car.leftOne, location[.leftOne]) != location[.leftOne]
                (location.becomes(location.updating(
                    .leftOne,
                    to: FormalCall(as: Int.self, "NextLocation", Car.leftOne, location[.leftOne])
                ))
                    && waiting.becomes(Expr<TupleExpr<Car>>(waiting.stateExpr).appending(Car.leftOne))
                ).when(FormalCall(as: Bool.self, "IsLeaving", Car.leftOne, location))
                    || (location.becomes(location.updating(
                        .leftOne,
                        to: FormalCall(as: Int.self, "NextLocation", Car.leftOne, location[.leftOne])
                    )) && waiting.stays).when(!FormalCall(as: Bool.self, "IsLeaving", Car.leftOne, location))
            }
            Action("MoveInside_l1") {
                FormalCall(as: SetExpr<Car>.self, "CarsOnBridge", location).contains(.leftOne)
                    && All(in: SetExpr<Car>.literal(.rightOne, .rightTwo, .leftOne, .leftTwo)) { car in
                        FormalCall(as: Int.self, "LocationAt", location, car.expr)
                            != FormalCall(as: Int.self, "NextLocation", Car.leftOne, location[.leftOne])
                    }
                (location.becomes(location.updating(
                    .leftOne,
                    to: FormalCall(as: Int.self, "NextLocation", Car.leftOne, location[.leftOne])
                ))
                    && waiting.becomes(Expr<TupleExpr<Car>>(waiting.stateExpr).appending(Car.leftOne))
                ).when(FormalCall(as: Bool.self, "IsLeaving", Car.leftOne, location))
                    || (location.becomes(location.updating(
                        .leftOne,
                        to: FormalCall(as: Int.self, "NextLocation", Car.leftOne, location[.leftOne])
                    )) && waiting.stays).when(!FormalCall(as: Bool.self, "IsLeaving", Car.leftOne, location))
            }
            Action("Enter_l1") {
                let waitingQueue = Expr<TupleExpr<Car>>(waiting.stateExpr)
                let nextCar = Expr<Car>(.tupleHead(waiting.stateExpr))
                waitingQueue.count > 0 && nextCar == Car.leftOne
                FormalCall(as: SetExpr<Car>.self, "CarsOnBridge", location).isEmpty
                    || (!FormalCall(as: SetExpr<Car>.self, "CarsOnBridge", location).contains(nextCar)
                        && All(in: FormalCall(as: SetExpr<Car>.self, "CarsOnBridge", location)) { car in
                            FormalCall(as: Bool.self, "IsRight", car.expr)
                                == FormalCall(as: Bool.self, "IsRight", Car.leftOne)
                        }
                        && All(in: SetExpr<Car>.literal(.rightOne, .rightTwo, .leftOne, .leftTwo)) { car in
                            FormalCall(as: Int.self, "LocationAt", location, car.expr)
                                != FormalCall(as: Int.self, "NextLocation", Car.leftOne, location[.leftOne])
                        })
                location.becomes(location.updating(
                    .leftOne,
                    to: FormalCall(as: Int.self, "NextLocation", Car.leftOne, location[.leftOne])
                ))
                waiting.becomes(Expr<TupleExpr<Car>>(waiting.tail))
            }

            Action("MoveOutside_l2") {
                !FormalCall(as: Bool.self, "InBridge", FormalCall(as: Int.self, "NextLocation", Car.leftTwo, location[.leftTwo]))
                    && FormalCall(as: Int.self, "NextLocation", Car.leftTwo, location[.leftTwo]) != location[.leftTwo]
                (location.becomes(location.updating(
                    .leftTwo,
                    to: FormalCall(as: Int.self, "NextLocation", Car.leftTwo, location[.leftTwo])
                ))
                    && waiting.becomes(Expr<TupleExpr<Car>>(waiting.stateExpr).appending(Car.leftTwo))
                ).when(FormalCall(as: Bool.self, "IsLeaving", Car.leftTwo, location))
                    || (location.becomes(location.updating(
                        .leftTwo,
                        to: FormalCall(as: Int.self, "NextLocation", Car.leftTwo, location[.leftTwo])
                    )) && waiting.stays).when(!FormalCall(as: Bool.self, "IsLeaving", Car.leftTwo, location))
            }
            Action("MoveInside_l2") {
                FormalCall(as: SetExpr<Car>.self, "CarsOnBridge", location).contains(.leftTwo)
                    && All(in: SetExpr<Car>.literal(.rightOne, .rightTwo, .leftOne, .leftTwo)) { car in
                        FormalCall(as: Int.self, "LocationAt", location, car.expr)
                            != FormalCall(as: Int.self, "NextLocation", Car.leftTwo, location[.leftTwo])
                    }
                (location.becomes(location.updating(
                    .leftTwo,
                    to: FormalCall(as: Int.self, "NextLocation", Car.leftTwo, location[.leftTwo])
                ))
                    && waiting.becomes(Expr<TupleExpr<Car>>(waiting.stateExpr).appending(Car.leftTwo))
                ).when(FormalCall(as: Bool.self, "IsLeaving", Car.leftTwo, location))
                    || (location.becomes(location.updating(
                        .leftTwo,
                        to: FormalCall(as: Int.self, "NextLocation", Car.leftTwo, location[.leftTwo])
                    )) && waiting.stays).when(!FormalCall(as: Bool.self, "IsLeaving", Car.leftTwo, location))
            }
            Action("Enter_l2") {
                let waitingQueue = Expr<TupleExpr<Car>>(waiting.stateExpr)
                let nextCar = Expr<Car>(.tupleHead(waiting.stateExpr))
                waitingQueue.count > 0 && nextCar == Car.leftTwo
                FormalCall(as: SetExpr<Car>.self, "CarsOnBridge", location).isEmpty
                    || (!FormalCall(as: SetExpr<Car>.self, "CarsOnBridge", location).contains(nextCar)
                        && All(in: FormalCall(as: SetExpr<Car>.self, "CarsOnBridge", location)) { car in
                            FormalCall(as: Bool.self, "IsRight", car.expr)
                                == FormalCall(as: Bool.self, "IsRight", Car.leftTwo)
                        }
                        && All(in: SetExpr<Car>.literal(.rightOne, .rightTwo, .leftOne, .leftTwo)) { car in
                            FormalCall(as: Int.self, "LocationAt", location, car.expr)
                                != FormalCall(as: Int.self, "NextLocation", Car.leftTwo, location[.leftTwo])
                        })
                location.becomes(location.updating(
                    .leftTwo,
                    to: FormalCall(as: Int.self, "NextLocation", Car.leftTwo, location[.leftTwo])
                ))
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
