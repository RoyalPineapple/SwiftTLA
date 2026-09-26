import Testing
import SwiftTLA
@testable import SwiftTLADemos

struct ElevatorBankDemoTests {
    @Test("car and passenger dictionaries retain Swift records and validate formal fields")
    func preservesRecordState() throws {
        let machine = try ElevatorBank.makeMachine()
        let cars: [ElevatorBank.CarID: ElevatorBank.Car] = machine.state.cars
        let riders: [ElevatorBank.Rider: ElevatorBank.Passenger] = machine.state.riders
        let car = try #require(cars[.carA])
        let rider = try #require(riders[.alice])
        #expect(ElevatorBank.Car(formalValue: car.tlaValue) == car)
        #expect(ElevatorBank.Passenger(formalValue: rider.tlaValue) == rider)
        #expect(ElevatorBank.Car(formalValue: .record([
            "floor": .int(4), "door": .string("closed"), "rider": .string("none")
        ])) == nil)
        #expect(ElevatorBank.Passenger(formalValue: .record([
            "phase": .string("waiting"), "floor": .int(1)
        ])) == nil)
    }

    @Test("descending travel updates only the selected car and passenger")
    func descendingTravelPreservesOtherEntries() throws {
        var machine = try ElevatorBank.makeMachine()
        let initial = machine.state
        for _ in 0..<6 { _ = try machine.send(.operate(process: .carB)) }
        #expect(machine.state.cars[.carB] == .init(floor: .one, door: .closed, rider: .none))
        #expect(machine.state.riders[.bob]?.phase == .arrived)
        #expect(machine.state.cars[.carA] == initial.cars[.carA])
        #expect(machine.state.riders[.alice] == initial.riders[.alice])
        #expect(machine.state.riders[ElevatorBank.Rider.none] == initial.riders[ElevatorBank.Rider.none])
    }

    @Test("Elevator bank machine boards, moves, and exits one rider")
    func machineBoardsMovesAndExits() throws {
        var machine = try ElevatorBank.makeMachine()
        #expect(machine.state.cars[.carA]?.floor == .one)
        #expect(machine.state.cars[.carA]?.door == .closed)
        #expect(machine.state.cars[.carA]?.rider == ElevatorBank.Rider.none)
        #expect(machine.state.riders[.alice]?.phase == .waiting)

        _ = try machine.send(.operate(process: .carA))
        #expect(machine.state.cars[.carA]?.door == .open)

        _ = try machine.send(.operate(process: .carA))
        #expect(machine.state.cars[.carA]?.door == .closed)
        #expect(machine.state.cars[.carA]?.rider == .alice)
        #expect(machine.state.riders[.alice]?.phase == .onboard)

        _ = try machine.send(.operate(process: .carA))
        #expect(machine.state.cars[.carA]?.floor == .two)
        _ = try machine.send(.operate(process: .carA))
        #expect(machine.state.cars[.carA]?.floor == .three)

        _ = try machine.send(.operate(process: .carA))
        #expect(machine.state.cars[.carA]?.door == .open)
        _ = try machine.send(.operate(process: .carA))
        #expect(machine.state.cars[.carA]?.rider == ElevatorBank.Rider.none)
        #expect(machine.state.cars[.carA]?.door == .closed)
        #expect(machine.state.riders[.alice]?.phase == .arrived)
    }
}
