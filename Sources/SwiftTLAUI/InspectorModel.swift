import Foundation
import Observation
import SwiftTLA

@MainActor
@Observable
public final class TLAMachineInspectorModel<Machine: TLAMachine & Hashable> {
    public private(set) var machine: Machine
    public private(set) var history: [Record] = []

    public struct Record: Identifiable {
        public let id = UUID()
        public let source: Machine
        public let transition: Machine.Transition
        public let destination: Machine
    }

    public init(machine: Machine = .initial) {
        self.machine = machine
    }

    public func apply(_ transition: Machine.Transition) {
        guard machine.availableTransitions.contains(transition) else { return }
        let source = machine
        machine.apply(transition)
        history.append(Record(source: source, transition: transition, destination: machine))
    }

    public func reset() {
        machine = .initial
        history.removeAll()
    }
}
