import SwiftTLA
import SwiftTLAMacros

/// Small, bounded K4 witness for a typed nested function/record update.
@TLAModel
public struct K4StructuredTLCWitness {
    public enum Car: String, CaseIterable, FiniteDomainKey {
        case left
        case right

        public static let formalDomain = allCases
        public static let formalTypeIdentity = FormalTypeIdentity(rawValue: "k4.structured-tlc-witness.car")

        public var tlaValue: TLAValue { .string(rawValue) }
    }

    public struct DoorFields {
        public let open: Bool
    }

    public enum Door: TLARecordSchema {
        public typealias Fields = DoorFields

        public static let fieldNames: Set<String> = ["open"]
        public static let defaultRecord: TLAValue = .record(["open": .bool(false)])

        public static func fieldName<Value>(for field: KeyPath<DoorFields, Value>) -> String? {
            field as AnyKeyPath == \DoorFields.open ? "open" : nil
        }

        public static let open = field(\DoorFields.open)
    }

    public static var spec: TLASpec {
        #spec("K4StructuredTLCWitness") {
            Algorithm("K4StructuredTLCWitness") {
                let doors = SharedVar(initial: Function<Car, Record<Door>>.literal(
                    (.left, Record<Door>.literal(.init(Door.open, false))),
                    (.right, Record<Door>.literal(.init(Door.open, false)))
                ))

                Each(Car.all) { car in
                    Do("openDoor") {
                        When(doors[car][Door.open] == false)
                        Assign(doors, to: doors.updating(car) { door in
                            door.updating(Door.open, to: true)
                        })
                    }
                }
            }
        }
    }
}
