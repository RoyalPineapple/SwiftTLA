import Foundation
import Testing
@testable import SwiftTLA
@testable import UpstreamParity

struct UpstreamParityTests {
    @Test("two-process Lock generated machine explores its complete bounded graph")
    func lockGeneratedGraph() throws {
        let graph = try ReachabilityGraph(initialMachines: LockModel.initialMachines(), maximumStates: 100)
        #expect(graph.transitions.count == Example.lockTwoProcess.expectedDistinct)
        #expect(graph.safetyViolations.isEmpty)
    }

    @Test("HourClock TLA+ module is TLC-shaped")
    func hourClockTLA() throws {
        let tla = try Example.hourClock.spec.compile().render().tlaBundle.tla
        #expect(tla.contains("MODULE HourClock"))
        #expect(tla.contains("hr \\in"))
        #expect(tla.contains("HCnxt"))
        #expect(tla.contains("Spec =="))
    }

    @Test("DieHard actions match upstream names")
    func dieHardNames() throws {
        let tla = try DieHardModel.render().tlaBundle.tla
        for name in ["FillSmallJug", "FillBigJug", "EmptySmallJug", "EmptyBigJug", "SmallToBig", "BigToSmall", "TypeOK", "NotSolved"] {
            #expect(tla.contains(name), "missing \(name)")
        }
    }

    @Test("Channel application transitions and complete checking agree for every upstream configuration")
    func channelGraphParity() throws {
        struct Edge: Hashable {
            let source: ChannelModel.Snapshot
            let action: ChannelModel.Action
            let target: ChannelModel.Snapshot
        }
        for scenario in try ChannelModel.validationScenarios() {
            let configuration = scenario.configuration
            let exploration = try scenario.explore(maximumStates: 100)
            let count = configuration.Data.count
            #expect(exploration.initialStates.count == 2 * count)
            #expect(exploration.initialStates.allSatisfy { $0.state.chan.ack == $0.state.chan.rdy })
            let checkedEdges = Set(exploration.transitions.flatMap { source, transitions in
                transitions.map { Edge(source: source, action: $0.action, target: $0.target) }
            })
            var pending = try scenario.initialMachines()
            #expect(Set(pending.map(\.snapshot)) == exploration.initialStates)
            #expect(throws: GeneratedMachineError.ambiguousInitialState) {
                try ChannelModel.makeMachine(configuration: configuration)
            }
            let datum = try #require(configuration.Data.first)
            #expect(throws: GeneratedMachineError.invalidInitialState) {
                try ChannelModel.makeMachine(.init(chan: .init(ack: 1, rdy: 0, val: datum)),
                    configuration: configuration)
            }
            let actions = configuration.Data.map { ChannelModel.Action.Send(d: $0) } + [.Rcv]
            var states: Set<ChannelModel.Snapshot> = []
            var edges: Set<Edge> = []
            while let machine = pending.popLast() {
                guard states.insert(machine.snapshot).inserted else { continue }
                try #require(states.count <= 4 * count)
                #expect(try machine.violatedInvariants(atLevel: 1).isEmpty)
                let enabled = try Set(machine.enabledActions())
                for action in actions {
                    let successors = try machine.successors(for: action)
                    #expect(try machine.isEnabled(action) == !successors.isEmpty)
                    #expect(enabled.contains(action) == !successors.isEmpty)
                    var next = machine
                    guard let successor = successors.first else {
                        #expect(throws: GeneratedMachineError.noMatchingSuccessor) { try next.send(action) }
                        #expect(next.state == machine.state)
                        continue
                    }
                    try #require(successors.count == 1)
                    let transition = try next.send(action)
                    #expect(transition.before == machine.state)
                    #expect(transition.after == successor.state)
                    #expect(next.state == successor.state)
                    edges.insert(Edge(source: machine.snapshot, action: action, target: next.snapshot))
                    pending.append(next)
                }
            }
            #expect(states == Set(exploration.transitions.keys))
            #expect(edges == checkedEdges)
            #expect(states.count == 4 * count)
            #expect(edges.count == 2 * count * (count + 1))
        }
    }

    @Test("AsynchInterface application transitions and complete checking agree for every upstream configuration")
    func asynchInterfaceGraphParity() throws {
        struct Edge: Hashable {
            let source: AsynchInterfaceModel.Snapshot
            let action: AsynchInterfaceModel.Action
            let target: AsynchInterfaceModel.Snapshot
        }
        for scenario in try AsynchInterfaceModel.validationScenarios() {
            let configuration = scenario.configuration
            let exploration = try scenario.explore(maximumStates: 100)
            let count = configuration.Data.count
            #expect(exploration.initialStates.count == 2 * count)
            #expect(exploration.initialStates.allSatisfy { $0.state.ack == $0.state.rdy })
            let checkedEdges = Set(exploration.transitions.flatMap { source, transitions in
                transitions.map { Edge(source: source, action: $0.action, target: $0.target) }
            })
            var pending = try scenario.initialMachines()
            #expect(Set(pending.map(\.snapshot)) == exploration.initialStates)
            #expect(throws: GeneratedMachineError.ambiguousInitialState) {
                try AsynchInterfaceModel.makeMachine(configuration: configuration)
            }
            let datum = try #require(configuration.Data.first)
            #expect(throws: GeneratedMachineError.invalidInitialState) {
                try AsynchInterfaceModel.makeMachine(.init(val: datum, rdy: 0, ack: 1),
                    configuration: configuration)
            }
            var states: Set<AsynchInterfaceModel.Snapshot> = []
            var edges: Set<Edge> = []
            let actions: [AsynchInterfaceModel.Action] = [.Send, .Rcv]
            while let machine = pending.popLast() {
                guard states.insert(machine.snapshot).inserted else { continue }
                try #require(states.count <= 4 * count)
                #expect(try machine.violatedInvariants(atLevel: 1).isEmpty)
                let enabled = try Set(machine.enabledActions())
                for action in actions {
                    let candidates = try machine.successors(for: action)
                    #expect(try machine.isEnabled(action) == !candidates.isEmpty)
                    #expect(enabled.contains(action) == !candidates.isEmpty)
                    var sent = machine
                    switch candidates.count {
                    case 0:
                        #expect(throws: GeneratedMachineError.noMatchingSuccessor) { try sent.send(action) }
                        #expect(sent.snapshot == machine.snapshot)
                    case 1:
                        let transition = try sent.send(action)
                        #expect(transition.before == machine.state)
                        #expect(transition.after == candidates[0].state)
                        #expect(sent.snapshot == candidates[0].snapshot)
                    default:
                        #expect(throws: GeneratedMachineError.ambiguousAction) { try sent.send(action) }
                        #expect(sent.snapshot == machine.snapshot)
                    }
                    for candidate in candidates {
                        edges.insert(Edge(source: machine.snapshot, action: action, target: candidate.snapshot))
                    }
                    pending.append(contentsOf: candidates)
                }
            }
            #expect(states == Set(exploration.transitions.keys))
            #expect(edges == checkedEdges)
            #expect(states.count == 4 * count)
            #expect(edges.count == 2 * count * (count + 1))
        }
    }

    @Test("configured Dijkstra populations preserve complete initial domains and the three-process graph")
    func dijkstraConfiguredPopulations() throws {
        let owner = try #require(TLAStateProjection.Token(validating: "k"))
        let firstFlag = try #require(TLAStateProjection.Token(validating: "b"))
        let secondFlag = try #require(TLAStateProjection.Token(validating: "c"))
        let control = try #require(TLAStateProjection.Token(validating: "pc"))
        let temporary = try #require(TLAStateProjection.Token(validating: "temp"))
        for population in [
            Set<DijkstraMutexModel.Process>([.one, .two, .three]),
            Set<DijkstraMutexModel.Process>([.one, .two, .three, .four]),
        ] {
            let initial = try DijkstraMutexModel.initialMachines(
                configuration: DijkstraMutexModel.Configuration(Proc: population))
            let members = Set(population.map(\.tlaValue))
            let flags = TLAValue.function(Dictionary(uniqueKeysWithValues: members.map { ($0, TLAValue.bool(true)) }))
            let controls = TLAValue.function(Dictionary(uniqueKeysWithValues: members.map { ($0, TLAValue.string("Li0")) }))
            let initialTemporary = TLAValue.function(Dictionary(uniqueKeysWithValues: members.map {
                ($0, TLAValue.constant("defaultInitValue"))
            }))
            #expect(initial.count == population.count)
            for machine in initial {
                let state = try machine.formalProjection(of: machine.snapshot)
                try #require(state.value(for: owner).map(members.contains) == true)
                #expect(state.value(for: firstFlag) == flags)
                #expect(state.value(for: secondFlag) == flags)
                #expect(state.value(for: control) == controls)
                #expect(state.value(for: temporary) == initialTemporary)
            }
        }
        let initial = try DijkstraMutexModel.initialMachines(
            configuration: DijkstraMutexModel.Configuration(Proc: [.one, .two, .three]))
        let graph = try ReachabilityGraph(
            initialMachines: initial,
            maximumStates: 100_000,
            checking: ModelChecks(properties: [.MutualExclusion])
        )
        #expect(graph.transitions.count == 90_882)
        #expect(graph.safetyViolations.isEmpty)
    }

    @Test("four-process Dijkstra scenario selects generated Spec, MutualExclusion, and deadlock")
    func dijkstraSafetyScenario() throws {
        #expect(try modelValidationScenarios().contains {
            $0.id == "dijkstra-mutex-0" && $0.scenario.name == "Safety4Processors"
        })
        let scenario = try #require(DijkstraMutexModel.validationScenarios().first)
        #expect(scenario.name == "Safety4Processors")
        #expect(scenario.configuration.Proc == Set<DijkstraMutexModel.Process>([.one, .two, .three, .four]))
        #expect(scenario.behavior == .specification)
        #expect(scenario.checking.properties == [.MutualExclusion])
        #expect(scenario.checking.checkDeadlock)
        #expect(Set(DijkstraMutexModel.Property.allCases) ==
            [.MutualExclusion, .DeadlockFree, .StarvationFree, .DeadlockFreedom])

        let rendered = try scenario.render()
        #expect(rendered.checkNames == ["MutualExclusion"])
        #expect(rendered.checksDeadlock)
        #expect(rendered.tlaBundle.root.tla.contains("DeadlockFree == (\\A _process \\in Proc:"))
        #expect(rendered.tlaBundle.root.tla.contains("StarvationFree == (\\A _process \\in Proc:"))
        #expect(rendered.tlaBundle.root.tla.contains("DeadlockFreedom == (\\A _process \\in Proc:"))
        let module = rendered.tlaBundle.root.tla
        let profileStart = try #require(module.range(of: "SwiftTLAProfile0 =="))
        let fairness = module[..<profileStart.lowerBound].split(separator: "\n").filter { $0.contains("WF_") }
        #expect(fairness.count == 1)
        let obligation = try #require(fairness.first)
        #expect(obligation.contains("\\A _process \\in Proc: WF_"))
        #expect(obligation.contains("Li0(_process)"))
        #expect(obligation.contains("ncs(_process)"))
        let configuration = try #require(rendered.tlaBundle.root.cfg)
        #expect(configuration.contains("SPECIFICATION Spec"))
        #expect(configuration.contains("INVARIANT MutualExclusion"))
        #expect(!configuration.contains("PROPERTY DeadlockFreedom"))
    }

    @Test("three-process Dijkstra liveness selects the published fairness profile and checks")
    func dijkstraLivenessScenario() throws {
        #expect(try modelValidationScenarios().contains {
            $0.id == "dijkstra-mutex-1" && $0.scenario.name == "Liveness3Processors"
        })
        let scenario = try #require(DijkstraMutexModel.validationScenarios().first {
            $0.name == "Liveness3Processors"
        })
        #expect(scenario.configuration.Proc == Set<DijkstraMutexModel.Process>([.one, .two, .three]))
        #expect(scenario.behavior == .specification)
        #expect(scenario.checking.properties == [.MutualExclusion, .DeadlockFreedom])
        #expect(scenario.checking.checkDeadlock)

        let rendered = try scenario.render()
        #expect(Set(rendered.checkNames) == ["MutualExclusion", "DeadlockFreedom"])
        let configuration = try #require(rendered.tlaBundle.root.cfg)
        #expect(configuration.contains("SPECIFICATION SwiftTLAProfile0"))
        #expect(configuration.contains("INVARIANT MutualExclusion"))
        #expect(configuration.contains("PROPERTY DeadlockFreedom"))
        let module = rendered.tlaBundle.root.tla
        let profile = try #require(module.components(separatedBy: "SwiftTLAProfile0 ==").last)
        let obligation = try #require(profile.split(separator: "\n").first { $0.contains("WF_") })
        #expect(obligation.contains("Li0(_process)"))
        #expect(!obligation.contains("ncs(_process)"))

        let plusCal = try rendered.plusCalBundle()
        #expect(plusCal.root.tla.contains("ncs:-"))
    }

    @Test("three-process Dijkstra generated checker completes its selected liveness")
    func dijkstraGeneratedLivenessCompletes() throws {
        let scenario = try #require(DijkstraMutexModel.validationScenarios().first {
            $0.name == "Liveness3Processors"
        })
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let report = try NativeValidationRunner.run(
            scenario: scenario, caseID: "dijkstra-mutex-1", maximumStates: 100_000, to: directory)
        #expect(report.graphComplete)
        #expect(report.initialStates == 3)
        #expect(report.states == 90_882)
        #expect(report.edges == 282_807)
        #expect(report.properties["MutualExclusion"] == .satisfied)
        #expect(report.properties["DeadlockFreedom"] == .satisfied)
        #expect(report.deadlock == .satisfied)
    }

    @Test("bounded Consensus fixture retains terminal deadlocks and temporal progress")
    func consensusGeneratedChecking() throws {
        let graph = try ReachabilityGraph(initialMachines: ConsensusModel.initialMachines(), maximumStates: 100)
        #expect(graph.transitions.count == Example.consensus.expectedDistinct)
        #expect(graph.safetyViolations.count == 3)
        #expect(graph.safetyViolations.values.allSatisfy { $0 == [.deadlock] })
        #expect(graph.temporalResults[.Success]?.status == .satisfied)
    }

    @Test("Reachable bounded source port checks its generated machine")
    func reachableBoundedPort() throws {
        let graph = try ReachabilityGraph(
            initialMachines: ReachableModel.initialMachines(),
            maximumStates: Example.reachable.maximumStateLimit
        )
        #expect(graph.transitions.count == Example.reachable.expectedDistinct)
        #expect(graph.safetyViolations.isEmpty)
    }

    @Test("Parallel Reachable bounded source port checks its generated machine")
    func parallelReachableBoundedPort() throws {
        let graph = try ReachabilityGraph(
            initialMachines: ParallelReachableModel.initialMachines(),
            maximumStates: Example.parallelReachable.maximumStateLimit
        )
        #expect(graph.transitions.count == Example.parallelReachable.expectedDistinct)
        #expect(graph.safetyViolations.isEmpty)
    }

    @Test("EWD998 uses typed finite functions and parameterized actions")
    func ewd998TypedFunctionParity() throws {
        let exploration = try explore(EWD998TerminationModel.spec, maximumStateLimit: 50_000)
        #expect(exploration.graph.states.count == Example.ewd998.expectedDistinct)
        #expect(isSuccessful(exploration))
    }
}

private func explore(_ spec: TLASpec, maximumStateLimit: Int) throws -> FiniteExploration {
    let compilation = try spec.compile()
    return try ModelChecker(
        compilation: compilation,
        configuration: try FiniteExplorationConfiguration(maximumStateLimit: maximumStateLimit, symmetryReduction: .disabled)
    ).explore()
}

private func isSuccessful(_ exploration: FiniteExploration) -> Bool {
    if case .ok = exploration.outcome { return true }
    return false
}
