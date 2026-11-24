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
        case moveOutsideBridge = "MoveOutsideBridge"
        case moveInsideBridge = "MoveInsideBridge"
        case enterBridge = "EnterBridge"
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
                Positions.allSatisfy { position in candidate <= position }
            }
            let EndPos = Select(from: Positions) { candidate in
                Positions.allSatisfy { position in candidate >= position }
            }
            let StartBridge = Select(from: Bridge) { candidate in
                Bridge.allSatisfy { position in candidate <= position }
            }
            let EndBridge = Select(from: Bridge) { candidate in
                Bridge.allSatisfy { position in candidate >= position }
            }

            let Location = scope.sharedVar(initial:
                Dictionary<Car, Int>.mapping(over: Cars) { car in
                    If(CarsRight.contains(car), then: EndPos, else: StartPos)
                })
            let WaitingBeforeBridge = scope.sharedVar(initial: Array<Car>([]))
            let CarsInBridge = Cars.filter { car in Bridge.contains(Location[car]) }
            let CarsInBridgeExitBridge = Temporal()
            let CarsEnterBridge = Temporal()

            let moveOutside = Do(Step.moveOutsideBridge, over: Cars) { car in
                let next = If(CarsRight.contains(car),
                    then: If(Location[car] > StartPos, then: Location[car] - 1, else: EndPos),
                    else: If(Location[car] < EndPos, then: Location[car] + 1, else: StartPos))
                When(!Bridge.contains(next))
                If(CarsRight.contains(car) && next == EndBridge + 1
                    || CarsLeft.contains(car) && next == StartBridge - 1) {
                    WaitingBeforeBridge.set(WaitingBeforeBridge.appending(car))
                }
                Location[car].set(next)
            }
            moveOutside

            let moveInside = Do(Step.moveInsideBridge, over: Cars) { car in
                let next = If(CarsRight.contains(car),
                    then: If(Location[car] > StartPos, then: Location[car] - 1, else: EndPos),
                    else: If(Location[car] < EndPos, then: Location[car] + 1, else: StartPos))
                When(CarsInBridge.contains(car)
                    && Cars.allSatisfy { other in Location[other] != next })
                If(CarsRight.contains(car) && next == EndBridge + 1
                    || CarsLeft.contains(car) && next == StartBridge - 1) {
                    WaitingBeforeBridge.set(WaitingBeforeBridge.appending(car))
                }
                Location[car].set(next)
            }
            moveInside

            let enterBridge = Do(Step.enterBridge, when: WaitingBeforeBridge.count > 0) {
                let car = WaitingBeforeBridge.head()
                let next = If(CarsRight.contains(car),
                    then: If(Location[car] > StartPos, then: Location[car] - 1, else: EndPos),
                    else: If(Location[car] < EndPos, then: Location[car] + 1, else: StartPos))
                let canFollow = !CarsInBridge.contains(car)
                    && CarsInBridge.allSatisfy { other in
                        CarsRight.contains(other) == CarsRight.contains(car)
                    }
                    && Cars.allSatisfy { other in Location[other] != next }
                When(CarsInBridge.isEmpty || canFollow)
                Location[car].set(next)
                WaitingBeforeBridge.set(WaitingBeforeBridge.tail())
            }
            enterBridge

            WeakFairness(each: moveOutside)
            WeakFairness(each: moveInside)
            WeakFairness(enterBridge)

            let invariants = Invariant("Invariants") {
                Cars.allSatisfy { first in
                    Cars.allSatisfy { second in
                        !(Bridge.contains(Location[first])
                            && Location[first] == Location[second]) || first == second
                    }
                }
                CarsInBridge.count < Bridge.count + 1
                CarsRight.allSatisfy { right in
                    CarsLeft.allSatisfy { left in
                        !(Bridge.contains(Location[right]) && Bridge.contains(Location[left]))
                    }
                }
            }
            invariants
            Invariant("TypeOK") {
                Functions(from: Cars, to: Positions).contains(Location)
                    && WaitingBeforeBridge.count <= Cars.count
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
            }.checking(only: [invariants, CarsInBridgeExitBridge, CarsEnterBridge])
            MC
        }
    }
}
