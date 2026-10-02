import SwiftTLA
import SwiftTLAMacros

// Upstream: specifications/SingleLaneBridge/SingleLaneBridge.tla, MC.tla, MC.cfg.
@TLAModel
package struct SingleLaneBridgeModel: Sendable {
    package enum Car: String, CaseIterable, FiniteTLAValueDomain {
        case rightOne = "r1"
        case rightTwo = "r2"
        case leftOne = "l1"
        case leftTwo = "l2"

        package static var defaultValue: Self { .rightOne }
        package static let finiteValues = allCases
        package var tlaValue: TLAValue { .string(rawValue) }
    }

    private enum Step: String, CaseIterable {
        case MoveOutsideBridge, MoveInsideBridge, EnterBridge
    }

    package static var spec: TLASpec {
        #spec("SingleLaneBridge") { scope in
            Extends(.naturals, .finiteSets, .sequences)
            let CarsRight = scope.parameter(as: Set<Car>.self,
                in: Set<Set<Car>>([Set([.rightOne, .rightTwo])]))
            let CarsLeft = scope.parameter(as: Set<Car>.self,
                in: Set<Set<Car>>([Set([.leftOne, .leftTwo])]))
            let Bridge = scope.parameter(as: Set<Int>.self,
                in: Set<Set<Int>>([Set([4, 5])]))
            let Positions = scope.parameter(as: Set<Int>.self,
                in: Set<Set<Int>>([Set([1, 2, 3, 4, 5, 6, 7, 8])]))
            let Cars = CarsRight.union(CarsLeft)
            let StartPos = Select(from: Positions) { candidate in
                ForAll(in: Positions) { position in candidate <= position }
            }
            let EndPos = Select(from: Positions) { candidate in
                ForAll(in: Positions) { position in candidate >= position }
            }
            let StartBridge = Select(from: Bridge) { candidate in
                ForAll(in: Bridge) { position in candidate <= position }
            }
            let EndBridge = Select(from: Bridge) { candidate in
                ForAll(in: Bridge) { position in candidate >= position }
            }

            let Location = scope.sharedVar(_name: "Location", initial:
                Dictionary<Car, Int>.mapping(over: Cars) { car in
                    If(CarsRight.contains(car), then: EndPos, else: StartPos)
                })
            let WaitingBeforeBridge = scope.sharedVar(_name: "WaitingBeforeBridge", initial: Array<Car>([]))
            let CarsInBridge = Cars.filtering { car in Bridge.contains(Location[car]) }
            let Invariants = Invariant()
            let TypeOK = Invariant()
            let CarsInBridgeExitBridge = Temporal()
            let CarsEnterBridge = Temporal()

            let moveOutside = Do(Step.MoveOutsideBridge, over: Cars) { car in
                let next = If(CarsRight.contains(car),
                    then: If(Location[car] > StartPos, then: Location[car] - 1, else: EndPos),
                    else: If(Location[car] < EndPos, then: Location[car] + 1, else: StartPos))
                When(!Bridge.contains(next))
                If(CarsRight.contains(car) && next == EndBridge + 1
                    || CarsLeft.contains(car) && next == StartBridge - 1) {
                    Assign(WaitingBeforeBridge, to: WaitingBeforeBridge.appending(car))
                }
                Assign(Location[car], to: next)
            }
            moveOutside

            let moveInside = Do(Step.MoveInsideBridge, over: Cars) { car in
                let next = If(CarsRight.contains(car),
                    then: If(Location[car] > StartPos, then: Location[car] - 1, else: EndPos),
                    else: If(Location[car] < EndPos, then: Location[car] + 1, else: StartPos))
                When(CarsInBridge.contains(car)
                    && ForAll(in: Cars) { other in Location[other] != next })
                If(CarsRight.contains(car) && next == EndBridge + 1
                    || CarsLeft.contains(car) && next == StartBridge - 1) {
                    Assign(WaitingBeforeBridge, to: WaitingBeforeBridge.appending(car))
                }
                Assign(Location[car], to: next)
            }
            moveInside

            let enterBridge = Do(Step.EnterBridge) {
                When(WaitingBeforeBridge.count > 0)
                let car = WaitingBeforeBridge.head()
                let next = If(CarsRight.contains(car),
                    then: If(Location[car] > StartPos, then: Location[car] - 1, else: EndPos),
                    else: If(Location[car] < EndPos, then: Location[car] + 1, else: StartPos))
                let canFollow = !CarsInBridge.contains(car)
                    && ForAll(in: CarsInBridge) { other in
                        CarsRight.contains(other) == CarsRight.contains(car)
                    }
                    && ForAll(in: Cars) { other in Location[other] != next }
                When(CarsInBridge.isEmpty || canFollow)
                Assign(Location[car], to: next)
                Assign(WaitingBeforeBridge, to: WaitingBeforeBridge.tail())
            }
            enterBridge

            WeakFairness(each: moveOutside)
            WeakFairness(each: moveInside)
            WeakFairness(enterBridge)

            Invariants {
                ForAll(in: Cars) { first in
                    ForAll(in: Cars) { second in
                        !(Bridge.contains(Location[first])
                            && Location[first] == Location[second]) || first == second
                    }
                }
                CarsInBridge.cardinality < Bridge.cardinality + 1
                ForAll(in: CarsRight) { right in
                    ForAll(in: CarsLeft) { left in
                        !(Bridge.contains(Location[right]) && Bridge.contains(Location[left]))
                    }
                }
            }
            TypeOK {
                Functions(from: Cars, to: Positions).contains(Location)
                    && WaitingBeforeBridge.count <= Cars.cardinality
            }

            CarsInBridgeExitBridge(.all([
                Bridge.contains(Location[Car.rightOne]).leadsTo(!Bridge.contains(Location[Car.rightOne])),
                Bridge.contains(Location[Car.rightTwo]).leadsTo(!Bridge.contains(Location[Car.rightTwo])),
                Bridge.contains(Location[Car.leftOne]).leadsTo(!Bridge.contains(Location[Car.leftOne])),
                Bridge.contains(Location[Car.leftTwo]).leadsTo(!Bridge.contains(Location[Car.leftTwo])),
            ]))
            CarsEnterBridge(.all([
                (!Bridge.contains(Location[Car.rightOne])).leadsTo(Bridge.contains(Location[Car.rightOne])),
                (!Bridge.contains(Location[Car.rightTwo])).leadsTo(Bridge.contains(Location[Car.rightTwo])),
                (!Bridge.contains(Location[Car.leftOne])).leadsTo(Bridge.contains(Location[Car.leftOne])),
                (!Bridge.contains(Location[Car.leftTwo])).leadsTo(Bridge.contains(Location[Car.leftTwo])),
            ]))

            let MC = Validation {
                Bind(CarsRight, to: Set<Car>([.rightOne, .rightTwo]))
                Bind(CarsLeft, to: Set<Car>([.leftOne, .leftTwo]))
                Bind(Bridge, to: Set<Int>([4, 5]))
                Bind(Positions, to: Set<Int>([1, 2, 3, 4, 5, 6, 7, 8]))
            }.checking(only: [Invariants, CarsInBridgeExitBridge, CarsEnterBridge])
            MC
        }
    }
}
