import SwiftTLA

public enum MultiCarElevator {
    public enum PersonID: String, CaseIterable, FiniteTLAValueDomain {
        case alice, bob

        public static let finiteValues = allCases
    }

    public enum CarID: String, CaseIterable, FiniteTLAValueDomain {
        case carA, carB

        public static let finiteValues = allCases
    }

    public enum FloorID: Int, CaseIterable, FiniteTLAValueDomain {
        case ground = 0, middle = 1, top = 2

        public static let finiteValues = allCases
    }

    public enum Direction: String, CaseIterable, FiniteTLAValueDomain {
        case up, down

        public static let finiteValues = allCases
    }

    public struct CarFields {
        public let floor: FloorID
        public let doorsOpen: Bool
        public let rider: String
    }

    public enum CarSchema: TLARecordSchema {
        public typealias Fields = CarFields

        public static let fieldNames: Set<String> = ["floor", "doorsOpen", "rider"]
        public static let defaultRecord: TLAValue = .record([
            "floor": .int(0), "doorsOpen": .bool(false), "rider": .string("none")
        ])

        public static func fieldName<Value>(for field: KeyPath<CarFields, Value>) -> String? {
            let key = field as AnyKeyPath
            if key == \CarFields.floor { return "floor" }
            if key == \CarFields.doorsOpen { return "doorsOpen" }
            if key == \CarFields.rider { return "rider" }
            return nil
        }

        public static let floor = field(\CarFields.floor)
        public static let doorsOpen = field(\CarFields.doorsOpen)
        public static let rider = field(\CarFields.rider)
    }

    public struct CallFields {
        public let person: PersonID
        public let floor: FloorID
        public let direction: Direction
    }

    public enum CallSchema: TLARecordSchema {
        public typealias Fields = CallFields

        public static let fieldNames: Set<String> = ["person", "floor", "direction"]
        public static let defaultRecord: TLAValue = .record([
            "person": .string("alice"), "floor": .int(0), "direction": .string("up")
        ])

        public static func fieldName<Value>(for field: KeyPath<CallFields, Value>) -> String? {
            let key = field as AnyKeyPath
            if key == \CallFields.person { return "person" }
            if key == \CallFields.floor { return "floor" }
            if key == \CallFields.direction { return "direction" }
            return nil
        }

        public static let person = field(\CallFields.person)
        public static let floor = field(\CallFields.floor)
        public static let direction = field(\CallFields.direction)
    }

    public static var spec: TLASpec {
        let cars = Var<Function<CarID, Record<CarSchema>>>("cars")
        let calls = Var<SetExpr<Record<CallSchema>>>("calls")
        let lastMoveDoorClosed = Var<Bool>("lastMoveDoorClosed")

        let floorValues = StateExpr.setLiteral(FloorID.tlaValues.map(StateExpr.value))
        let riderValues = StateExpr.setLiteral([
            .value(.string("none")), .value(PersonID.alice.tlaValue), .value(PersonID.bob.tlaValue)
        ])

        func car(_ value: StateExpr) -> StateExpr {
            .functionApply(cars.stateExpr, value)
        }

        func carField(_ value: StateExpr, _ field: String) -> StateExpr {
            .recordAccess(car(value), field)
        }

        func updatingCar(_ value: StateExpr, field: String, to replacement: StateExpr) -> Expr<Function<CarID, Record<CarSchema>>> {
            Expr(.except(
                cars.stateExpr,
                value,
                .except(car(value), .value(.string(field)), replacement)
            ))
        }

        func boundCall() -> Expr<Record<CallSchema>> {
            Record<CallSchema>.literal(
                .init(CallSchema.person, Expr(.variable("person"))),
                .init(CallSchema.floor, Expr(.variable("floor"))),
                .init(CallSchema.direction, Expr(.variable("direction")))
            )
        }

        func noCarCarries(_ person: StateExpr) -> StateExpr {
            carField(.value(CarID.carA.tlaValue), "rider") != person
                && carField(.value(CarID.carB.tlaValue), "rider") != person
        }

        return #spec("MultiCarElevator") {
            Variable(cars, TLAValue.function([
                CarID.carA.tlaValue: TLAValue.record([
                    "floor": FloorID.ground.tlaValue,
                    "doorsOpen": .bool(false),
                    "rider": .string("none")
                ]),
                CarID.carB.tlaValue: TLAValue.record([
                    "floor": FloorID.top.tlaValue,
                    "doorsOpen": .bool(false),
                    "rider": .string("none")
                ])
            ]))
            Variable(calls, TLAValue.set([]))
            Variable(lastMoveDoorClosed, true)
            Constraint(calls.stateExpr.cardinality <= 1)

            Invariant("TypeOK") {
                cars[.carA][CarSchema.floor].raw.isIn(floorValues)
                    && cars[.carB][CarSchema.floor].raw.isIn(floorValues)
                    && carField(.value(CarID.carA.tlaValue), "rider").isIn(riderValues)
                    && carField(.value(CarID.carB.tlaValue), "rider").isIn(riderValues)
            }
            Invariant("FloorBounds") {
                cars[.carA][CarSchema.floor].raw >= 0
                    && cars[.carA][CarSchema.floor].raw <= 2
                    && cars[.carB][CarSchema.floor].raw >= 0
                    && cars[.carB][CarSchema.floor].raw <= 2
            }
            Invariant("ClosedDoorMovement") { lastMoveDoorClosed == true }
            Invariant("NoDoubleAssignment") {
                carField(.value(CarID.carA.tlaValue), "rider") == "none"
                    || carField(.value(CarID.carB.tlaValue), "rider") == "none"
                    || carField(.value(CarID.carA.tlaValue), "rider")
                        != carField(.value(CarID.carB.tlaValue), "rider")
            }

            Action("request", parameters: [
                ActionParameter("person", values: PersonID.finiteValues),
                ActionParameter("floor", values: FloorID.finiteValues),
                ActionParameter("direction", values: Direction.finiteValues)
            ]) {
                !calls.contains(boundCall()) && calls.inserting(boundCall())
            }
            Action("assign", parameters: [
                ActionParameter("person", values: PersonID.finiteValues),
                ActionParameter("car", values: CarID.finiteValues),
                ActionParameter("direction", values: Direction.finiteValues)
            ]) {
                calls.stateExpr.cardinality == 1
                    && noCarCarries(.variable("person"))
                    && carField(.variable("car"), "rider") == "none"
                    && cars.becomes(updatingCar(.variable("car"), field: "rider", to: .variable("person")))
            }
            Action("move", parameters: [
                ActionParameter("car", values: CarID.finiteValues),
                ActionParameter("direction", values: Direction.finiteValues),
                ActionParameter("floor", values: FloorID.finiteValues)
            ]) {
                carField(.variable("car"), "doorsOpen") == false
                    && carField(.variable("car"), "floor") != Expr<FloorID>(.variable("floor"))
                    && cars.becomes(updatingCar(.variable("car"), field: "floor", to: .variable("floor")))
                    && lastMoveDoorClosed.becomes(true)
            }
            Action("openDoor", parameters: [
                ActionParameter("car", values: CarID.finiteValues),
                ActionParameter("floor", values: FloorID.finiteValues),
                ActionParameter("direction", values: Direction.finiteValues)
            ]) {
                carField(.variable("car"), "doorsOpen") == false
                    && cars.becomes(updatingCar(.variable("car"), field: "doorsOpen", to: .value(.bool(true))))
            }
            Action("board", parameters: [
                ActionParameter("person", values: PersonID.finiteValues),
                ActionParameter("car", values: CarID.finiteValues),
                ActionParameter("floor", values: FloorID.finiteValues)
            ]) {
                carField(.variable("car"), "doorsOpen") == true
                    && carField(.variable("car"), "rider") == .variable("person")
                    && calls.removing(Record<CallSchema>.literal(
                        .init(CallSchema.person, Expr(.variable("person"))),
                        .init(CallSchema.floor, Expr(.variable("floor"))),
                        .init(CallSchema.direction, .up)
                    ))
            }
            Action("closeDoor", parameters: [
                ActionParameter("car", values: CarID.finiteValues),
                ActionParameter("floor", values: FloorID.finiteValues),
                ActionParameter("direction", values: Direction.finiteValues)
            ]) {
                carField(.variable("car"), "doorsOpen") == true
                    && cars.becomes(updatingCar(.variable("car"), field: "doorsOpen", to: .value(.bool(false))))
            }
            Action("completeRide", parameters: [
                ActionParameter("person", values: PersonID.finiteValues),
                ActionParameter("car", values: CarID.finiteValues),
                ActionParameter("floor", values: FloorID.finiteValues)
            ]) {
                carField(.variable("car"), "doorsOpen") == true
                    && carField(.variable("car"), "rider") == .variable("person")
                    && carField(.variable("car"), "floor") == .variable("floor")
                    && cars.becomes(updatingCar(.variable("car"), field: "rider", to: .value(.string("none"))))
            }
        }
    }
}

extension Example {
    public static let multiCarElevator = Entry(
        id: "elevator/MultiCarElevator",
        upstreamSpec: "multicar-elevator",
        upstreamModule: "Verification/CoreConformance/fixtures/multicar-elevator/MultiCarElevator.tla",
        upstreamCfg: nil,
        expectedDistinct: 3_276,
        spec: MultiCarElevator.spec,
        notes: "Bounded two-person, two-car, three-floor typed safety fixture."
    )
}
