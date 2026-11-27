import BenchModels
import Darwin
import Dispatch
import Foundation
import SwiftTLA

typealias Operation = () throws -> Int

// Keep the control in optimized Swift while forcing the result through a real call.
struct HandState {
    var tick = 0
    var counts: [Int: Int]
    @inline(never) mutating func touch() -> (HandState, HandState) {
        let before = self
        counts[1]! += 1
        return (before, self)
    }
    @inline(never) mutating func touchInPlace() -> Int {
        counts[1]! += 1
        return counts[1]!
    }
    @inline(never) mutating func increment() -> (Int, Int) {
        let before = tick
        tick += 1
        return (before, tick)
    }
}

@inline(never) func updatingExistingKey(_ table: [Int:Int], _ key: Int, _ value: Int) -> [Int:Int] {
    guard table[key] != nil else { return table }
    var updated = table
    updated[key] = value
    return updated
}

@inline(never) func handAppend(_ original: [Int]) -> Int {
    var updated = original
    updated.append(0)
    // Observe the new contents across a real call so the optimizer must materialize the buffer.
    return observeArray(updated)
}

@inline(never) func observeArray(_ values: [Int]) -> Int {
    values.count + (values.last ?? 0)
}

func operation(_ name: String, _ size: Int) throws -> Operation {
    switch name {
    case "clock":
        var i = 0
        return { i += 1; return i }
    case "hand.increment":
        var m = HandState(counts: [:])
        return { let (a,b) = m.increment(); return a ^ b }
    case "hand.touch", "hand.inPlace":
        var m = HandState(counts: Dictionary(uniqueKeysWithValues: (1...size).map { ($0,0) }))
        if name == "hand.inPlace" { return { m.touchInPlace() } }
        return { let (a,b) = m.touch(); return a.counts[1]! ^ b.counts[1]! }
    case "hand.sameStorage", "helper.touch", "hand.checkedTouch":
        let config = try Inventory.Configuration(size: size)
        var m = try HandState(counts: Inventory.makeMachine(configuration: config).state.counts)
        if name == "hand.sameStorage" {
            return { let (a,b) = m.touch(); return a.counts[1]! ^ b.counts[1]! }
        }
        if name == "hand.checkedTouch" { return {
            let before = m
            let x = try _NativeMachineOperations.functionValue(m.counts, at: 1)
            m.counts = updatingExistingKey(m.counts, 1, x + 1)
            return before.counts[1]! ^ m.counts[1]!
        } }
        return {
            let before = m
            let x = try _NativeMachineOperations.functionValue(m.counts, at: 1)
            m.counts = _NativeMachineOperations.functionUpdated(m.counts, at: 1, to: x + 1)
            return before.counts[1]! ^ m.counts[1]!
        }
    case "hand.append":
        let original = Array(repeating: 0, count: size)
        return { handAppend(original) }
    case "pulse.make": return { try Pulse.makeMachine().state.count }
    case "pulse.send", "pulse.blocked", "pulse.failure", "pulse.enabled":
        var m = try Pulse.makeMachine()
        switch name {
        case "pulse.send": return { let t = try m.send(.increment); return t.before.count ^ t.after.count }
        case "pulse.enabled": return { try m.isEnabled(.increment) ? 1 : 0 }
        case "pulse.blocked": return {
            do { _ = try m.send(.blocked); preconditionFailure("guard accepted") }
            catch GeneratedMachineError.noMatchingSuccessor { precondition(m.state.count == 0); return 1 }
        }
        default: return {
            do { _ = try m.send(.fail); preconditionFailure("division succeeded") }
            catch NativeMachineEvaluationError.divisionByZero { precondition(m.state.count == 0); return 1 }
        }
        }
    case "inventory.make", "inventory.touch", "inventory.increment", "inventory.keep32", "inventory.discard",
         "inventory.project", "inventory.invariant", "inventory.hash", "inventory.append":
        let config = try Inventory.Configuration(size: size)
        if name == "inventory.make" {
            return { try Inventory.makeMachine(configuration: config).state.counts.count }
        }
        var m = try Inventory.makeMachine(configuration: config)
        switch name {
        case "inventory.discard": return { _ = try m.send(.touch); return m.state.counts[1]! }
        case "inventory.touch": return { let t = try m.send(.touch); return t.before.counts[1]! ^ t.after.counts[1]! }
        case "inventory.increment": return { let t = try m.send(.increment); return t.before.tick ^ t.after.tick }
        case "inventory.keep32":
            var history = Array(repeating: m.state, count: 32)
            var index = 0
            return {
                let t = try m.send(.touch)
                let old = history[index].counts[1]!
                history[index] = t.before
                index = (index + 1) % history.count
                return old ^ t.after.counts[1]!
            }
        case "inventory.hash": return { m.snapshot.hashValue }
        case "inventory.project": return { try m.formalProjection(of: m.snapshot).entries.count }
        case "inventory.invariant": return { try m.violatedInvariants(atLevel: 0).count }
        default:
            for _ in 0..<size { _ = try m.send(.append) }
            let original = m
            return {
                var copy = original
                let t = try copy.send(.append)
                precondition(t.before.queue.count == size)
                return observeArray(t.after.queue)
            }
        }
    case "choices.initials", "choices.selected", "choices.ambiguousInit", "choices.send", "choices.enabled", "choices.successors":
        let config = try Choices.Configuration(size: size)
        if name == "choices.initials" { return { try Choices.initialMachines(configuration: config).count } }
        if name == "choices.selected" { return { try Choices.makeMachine(.init(value: size), configuration: config).state.value } }
        if name == "choices.ambiguousInit" { return {
            do { _ = try Choices.makeMachine(configuration: config); preconditionFailure("expected ambiguous initial") }
            catch GeneratedMachineError.ambiguousInitialState { return size }
        } }
        var m = try Choices.makeMachine(.init(value: size), configuration: config)
        if name == "choices.enabled" { return { try m.isEnabled(.pick) ? 1 : 0 } }
        if name == "choices.successors" { return { try m.successors(for: .pick).count } }
        return {
            do { _ = try m.send(.pick); preconditionFailure("expected ambiguous action") }
            catch GeneratedMachineError.ambiguousAction { precondition(m.state.value == size); return 1 }
        }
    case "counter.cycle", "counter.graph", "counter.render":
        let config = try ConfiguredCounter.Configuration(limit: size, stopAtLimit: true)
        if name == "counter.graph" { return {
            let g = try ReachabilityGraph(initialMachines: ConfiguredCounter.initialMachines(configuration: config), maximumStates: size + 2)
            precondition(g.safetyViolations.isEmpty && g.transitions.count == size + 1)
            return g.transitions.count
        } }
        if name == "counter.render" { return {
            let bundle = try ConfiguredCounter.render(configuration: config).tlaBundle
            return bundle.tla.utf8.count + bundle.cfg.utf8.count
        } }
        let initial = try ConfiguredCounter.makeMachine(configuration: config)
        let action = try initial.actionCandidates().first!
        return {
            var m = initial
            for _ in 0..<size { _ = try m.send(action) }
            precondition(m.state.value == size && m.state.previous == size - 1 && m.state.copied == size)
            return m.state.value
        }
    case "nano.initial", "nano.successors", "nano.invariants", "nano.project":
        let config = try NanoBlockchainModel.Configuration(Hash: [.h1,.h2,.h3,.h4])
        if name == "nano.initial" { return { try NanoBlockchainModel.makeMachine(configuration: config).state.distributedLedger.count } }
        let initial = try NanoBlockchainModel.makeMachine(configuration: config)
        let action = try initial.actionCandidates().first!
        let next = try initial.successors(for: action)
        precondition(!next.isEmpty)
        if name == "nano.successors" { return { try initial.successors(for: action).count } }
        let m = next[0]
        if name == "nano.invariants" { return { try m.violatedInvariants(atLevel: 1).count } }
        return { try m.formalProjection(of: m.snapshot).entries.count }
    case "coffee.send", "coffee.graph":
        let config = try CoffeeCanModel.Configuration(MaxBeanCount: size)
        if name == "coffee.graph" {
            let initials = try CoffeeCanModel.initialMachines(configuration: config)
            return {
                let g = try ReachabilityGraph(initialMachines: initials, maximumStates: initials.count + 1)
                precondition(g.transitions.count == initials.count && g.temporalResults.count == 4)
                return g.transitions.count
            }
        }
        let initial = try CoffeeCanModel.initialMachines(configuration: config).first { $0.state.can.black == size && $0.state.can.white == 0 }!
        let action = try initial.actionCandidates().first { try initial.formalCall(for: $0).name == "PickSameColorBlack" }!
        return {
            var m = initial
            let t = try m.send(action)
            precondition(t.after.can.black == size - 1 && t.before.can.black == size)
            return t.after.can.black
        }
    case "fifo.cycle":
        let config = try BoundedFIFOModel.Configuration(Message: [.m1,.m2,.m3], constrainQueue: true, qLen: 3)
        var m = try BoundedFIFOModel.initialMachines(configuration: config).first!
        let candidates = try m.actionCandidates()
        let actions = try ["SSend","BufRcv","BufSend","RRcv"].map { name in
            try candidates.first { try m.formalCall(for: $0).name == name }!
        }
        return {
            for action in actions { _ = try m.send(action) }
            precondition(m.state.q.isEmpty && m.state.out.ack == m.state.out.rdy && m.state.in.val == m.state.out.val)
            return m.state.out.ack
        }
    default: fatalError("unknown scenario: " + name)
    }
}

func actorBurst(_ actor: isolated Pulse.Actor, _ count: Int) throws -> Int {
    var total = 0
    for _ in 0..<count {
        let t = try actor.send(.increment)
        total &+= t.before.count ^ t.after.count
    }
    return total
}

let arguments = CommandLine.arguments
if arguments.count == 2 && arguments[1] == "layout" {
    func layout<T>(_ name: String, _: T.Type) -> [String: Any] {
        ["type":name,"size":MemoryLayout<T>.size,"stride":MemoryLayout<T>.stride,"alignment":MemoryLayout<T>.alignment]
    }
    let rows = [
        layout("Int",Int.self), layout("[Int:Int]",[Int:Int].self), layout("[Int]",[Int].self),
        layout("Pulse.State",Pulse.State.self), layout("Pulse.Action",Pulse.Action.self),
        layout("Pulse.Snapshot",Pulse.Snapshot.self), layout("Pulse.Transition",Pulse.Transition.self),
        layout("Inventory.State",Inventory.State.self), layout("Inventory.Snapshot",Inventory.Snapshot.self),
        layout("Inventory.Transition",Inventory.Transition.self), layout("ConfiguredCounter.State",ConfiguredCounter.State.self),
        layout("ConfiguredCounter.Snapshot",ConfiguredCounter.Snapshot.self), layout("BoundedFIFO.State",BoundedFIFOModel.State.self),
        layout("CoffeeCan.State",CoffeeCanModel.State.self), layout("Nano.State",NanoBlockchainModel.State.self),
        layout("Nano.Snapshot",NanoBlockchainModel.Snapshot.self), layout("Nano.Transition",NanoBlockchainModel.Transition.self)
    ]
    print(String(decoding: try JSONSerialization.data(withJSONObject: rows), as: UTF8.self))
    exit(0)
}
precondition(arguments.count == 5, "scenario size iterations batches")
let name = arguments[1], size = Int(arguments[2])!, iterations = Int(arguments[3])!, batches = Int(arguments[4])!
precondition(min(size, iterations, batches) > 0)
let body: Operation = name.hasPrefix("pulse.actor") ? { 0 } : try operation(name, size)
let actor = name.hasPrefix("pulse.actor") ? try Pulse.Actor() : nil
var checksum = 0
func now() -> UInt64 { DispatchTime.now().uptimeNanoseconds }
let firstStart = now()
if let actor { let t = try await actor.send(.increment); checksum &+= t.before.count ^ t.after.count }
else { checksum &+= try body() }
let first = now() - firstStart
var samples: [UInt64] = [], totals: [UInt64] = []
for _ in 0..<batches {
    let start = now()
    if let actor, name == "pulse.actorBurst" {
        checksum &+= try await actorBurst(actor, iterations)
    } else if let actor {
        for _ in 0..<iterations {
            let t = try await actor.send(.increment)
            checksum &+= t.before.count ^ t.after.count
        }
    } else {
        for _ in 0..<iterations { checksum &+= try body() }
    }
    totals.append(now() - start)
}
for _ in 0..<min(128, iterations * batches) {
    let start = now()
    if let actor { let t = try await actor.send(.increment); checksum &+= t.before.count ^ t.after.count }
    else { checksum &+= try body() }
    samples.append(now() - start)
}
var heap: [String: UInt64] = [:]
if ProcessInfo.processInfo.environment["BENCH_ALLOCATIONS"] == "1" {
    typealias Switch = @convention(c) () -> Void
    typealias Count = @convention(c) () -> UInt64
    let handle = UnsafeMutableRawPointer(bitPattern: -2)
    func symbol<T>(_ name: String, _ type: T.Type) -> T {
        guard let ptr = dlsym(handle, name) else { fatalError("missing probe symbol " + name) }
        return unsafeBitCast(ptr, to: type)
    }
    let begin = symbol("bench_begin", Switch.self), end = symbol("bench_end", Switch.self)
    let events = symbol("bench_events", Count.self), bytes = symbol("bench_bytes", Count.self)
    begin()
    let probe = malloc(257)!
    end()
    // Pass the pointer to an opaque C entry point to keep the allocation observable in release.
    let release = symbol("free", (@convention(c) (UnsafeMutableRawPointer?) -> Void).self)
    release(probe)
    guard events() == 1 && bytes() == 257 else {
        FileHandle.standardError.write(Data("allocator control failed: \(events()) events, \(bytes()) bytes\n".utf8))
        exit(2)
    }
    precondition(actor == nil)
    begin()
    for _ in 0..<iterations { checksum &+= try body() }
    end()
    heap = ["events":events(),"requestedBytes":bytes(),"calls":UInt64(iterations)]
}
let report: [String: Any] = ["heap":heap,"name":name,"size":size,"iterations":iterations,"firstNS":first,
    "batchNS":totals,"singleNS":samples,"checksum":checksum]
print(String(decoding: try JSONSerialization.data(withJSONObject: report), as: UTF8.self))
