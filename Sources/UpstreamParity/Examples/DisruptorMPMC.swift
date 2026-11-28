// Multiple producers claim positions and write into a circular buffer while several readers track their own positions.
// https://github.com/tlaplus/Examples/blob/ceeaa904140e3e03781cb2a79cd6c6d8b8b08e10/specifications/Disruptor/Disruptor_MPMC.tla

import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct DisruptorMPMCModel: Sendable {
    package enum ThreadID: String, CaseIterable, FiniteTLAValueDomain {
        case w1, w2, r1, r2, r3
        package static let finiteValues = allCases
        package static var defaultValue: Self { .w1 }
        package var tlaValue: TLAValue { .constant(rawValue) }
    }
    package enum Empty: String, CaseIterable, FiniteTLAValueDomain {
        case null = "NULL"
        package static let finiteValues = allCases
        package static var defaultValue: Self { .null }
        package var tlaValue: TLAValue { .constant(rawValue) }
    }
    package typealias Slot = OneOf<Int, Empty>
    package struct Buffer: Hashable, Sendable {
        package let slots: [Int: Slot]
        package let readers: [Int: Set<ThreadID>]
        package let writers: [Int: Set<ThreadID>]
    }
    package struct ReadPosition: Hashable, Sendable {
        package let reader: ThreadID
        package let sequence: Int
    }
    private enum Step: String, CaseIterable {
        case beginWrite = "BeginWrite", endWrite = "EndWrite", beginRead = "BeginRead", endRead = "EndRead"
    }
    package static var spec: TLASpec {
        #spec("MCDisruptor_MPMC") { scope in
            Extends(.integers, .sequences, .finiteSets)
            let writers = scope.parameter(tlaName: "Writers", as: Set<ThreadID>.self, in: Subsets(of: Set<ThreadID>([ThreadID.w1, ThreadID.w2])))
            let readers = scope.parameter(tlaName: "Readers", as: Set<ThreadID>.self, in: Subsets(of: Set<ThreadID>([ThreadID.r1, ThreadID.r2, ThreadID.r3])))
            let bufferSize = scope.parameter(tlaName: "Size", as: Int.self, in: Int.all)
            let maxPublished = scope.parameter(tlaName: "MaxPublished", as: Int.self, in: Int.all)
            // NULL is the model value; NULL_1 is its parameter in the generated CFG.
            let emptySlot = scope.parameter(tlaName: "NULL_1", as: Empty.self, in: Set<Empty>([Empty.null]))
            Assume(!writers.isEmpty && !readers.isEmpty && writers.intersection(readers).isEmpty)
            Assume(bufferSize > 0 && maxPublished > 0)
            let threads = writers.union(readers)
            let indices = IntRange(0, through: bufferSize - 1)
            let emptyAccess = Dictionary<Int, Set<ThreadID>>.mapping(over: indices) { _ in Set<ThreadID>() }
            let ringBuffer = scope.sharedVar(tlaName: "ringbuffer", initial: Buffer.expression(
                slots: Dictionary<Int, Slot>.mapping(over: indices) { _ in Slot.second(emptySlot) },
                readers: emptyAccess, writers: emptyAccess))
            let nextSequence = scope.sharedVar(tlaName: "next_sequence", initial: 0)
            let claimedSequence = scope.sharedVar(tlaName: "claimed_sequence", initial: Dictionary<ThreadID, Int>.mapping(over: writers) { _ in -1 })
            let published = scope.sharedVar(initial: Dictionary<Int, Bool>.mapping(over: indices) { _ in false })
            let read = scope.sharedVar(initial: Dictionary<ThreadID, Int>.mapping(over: readers) { _ in -1 })
            let consumed = scope.sharedVar(initial: Dictionary<ThreadID, [Int]>.mapping(over: readers) { _ in [Int]() })
            let pc = scope.sharedVar(initial: Dictionary<ThreadID, String>.mapping(over: threads) { _ in "Advance" })

            // Each lap reuses the slot and reverses the bit that means published.
            FormalDefinition("IsPublished", taking: Int.self) { sequence -> Expr<Bool> in
                published[sequence % bufferSize] == ((sequence / bufferSize) % 2 == 0)
            }

            Do(Step.beginWrite, over: writers) { writer in
                let sequence = nextSequence
                let slotIndex = sequence % bufferSize
                When(readers.allSatisfy { reader in read[reader] >= sequence - bufferSize })
                When(pc[writer] == "Advance")
                claimedSequence[writer].set(sequence)
                pc[writer].set("Access")
                ringBuffer.writers[slotIndex].insert(writer)
                ringBuffer.slots[slotIndex].set(Slot.first(sequence))
                nextSequence.set(sequence + 1)
            }
            Do(Step.endWrite, over: writers) { writer in
                let sequence = claimedSequence[writer]
                let slotIndex = sequence % bufferSize
                When(pc[writer] == "Access")
                pc[writer].set("Advance")
                ringBuffer.writers[slotIndex].remove(writer)
                published[slotIndex].set(!published[slotIndex])
            }
            let beginRead = Do(Step.beginRead, over: readers) { reader in
                let sequence = read[reader] + 1
                let slotIndex = sequence % bufferSize
                When(pc[reader] == "Advance" && FormalCall(as: Bool.self, "IsPublished", sequence))
                pc[reader].set("Access")
                ringBuffer.readers[slotIndex].insert(reader)
                consumed[reader].set(consumed[reader].appending(ringBuffer.slots[slotIndex].assuming(Int.self)))
            }
            let endRead = Do(Step.endRead, over: readers) { reader in
                let sequence = read[reader] + 1
                let slotIndex = sequence % bufferSize
                When(pc[reader] == "Access")
                pc[reader].set("Advance")
                ringBuffer.readers[slotIndex].remove(reader)
                read[reader].set(sequence)
            }
            WeakFairness(each: beginRead)
            WeakFairness(each: endRead)
            Constraint(nextSequence <= maxPublished)
            let NoDataRaces = Invariant()
            NoDataRaces {
                indices.allSatisfy { i in
                    (ringBuffer.readers[i].isEmpty || ringBuffer.writers[i].isEmpty) && ringBuffer.writers[i].count <= 1
                }
            }
            let TypeOk = Invariant()
            TypeOk {
                ringBuffer.slots.keys == indices && ringBuffer.readers.keys == indices && ringBuffer.writers.keys == indices
                indices.allSatisfy { i in
                    (ringBuffer.slots[i] == Slot.second(emptySlot) || Int.all.contains(ringBuffer.slots[i].assuming(Int.self))) &&
                    ringBuffer.readers[i].isSubset(of: readers) && ringBuffer.writers[i].isSubset(of: writers)
                }
                nextSequence >= 0 && Functions(from: writers, to: Int.all).contains(claimedSequence)
                Functions(from: indices, to: Bool.all).contains(published)
                Functions(from: readers, to: Int.all).contains(read)
                Functions(from: threads, to: Set<String>(["Advance", "Access"])).contains(pc)
                consumed.keys == readers && readers.allSatisfy { r in
                    IntRange(1, through: consumed[r].count).allSatisfy { i in consumed[r][i] >= 0 }
                }
            }
            let subjects = readers.flatMapping { r in IntRange(0, through: maxPublished - 1).mapping { i in
                ReadPosition.expression(reader: r, sequence: i)
            } }
            let claimedSequences = writers.mapping { writer in claimedSequence[writer] }
            let minimumClaim = Select(from: claimedSequences) { sequence in
                writers.allSatisfy { writer in sequence <= claimedSequence[writer] }
            }
            let availableSequence = Select(from: claimedSequences.inserting(minimumClaim - 1)) { candidate in
                !FormalCall(as: Bool.self, "IsPublished", candidate) || !writers.contains { writer in
                    claimedSequence[writer] == candidate + 1
                        && FormalCall(as: Bool.self, "IsPublished", claimedSequence[writer])
                }
            }
            let Liveliness = Temporal()
            Liveliness(forEach: subjects) { pair in
                .eventuallyAlways(pair.sequence > availableSequence || (consumed[pair.reader].count >= pair.sequence + 1 &&
                    consumed[pair.reader][pair.sequence + 1] == pair.sequence))
            }
            Validation("Upstream") {
                Bind(writers, to: Set<ThreadID>([ThreadID.w1, ThreadID.w2]))
                Bind(readers, to: Set<ThreadID>([ThreadID.r1, ThreadID.r2, ThreadID.r3]))
                Bind(bufferSize, to: 4)
                Bind(maxPublished, to: 10)
                Bind(emptySlot, to: Empty.null)
            }.checking(only: [TypeOk, NoDataRaces]).checkingDeadlock(false)
            Validation("LivelinessCheck") {
                Bind(writers, to: Set<ThreadID>([ThreadID.w1, ThreadID.w2]))
                Bind(readers, to: Set<ThreadID>([ThreadID.r1, ThreadID.r2]))
                Bind(bufferSize, to: 4)
                Bind(maxPublished, to: 10)
                Bind(emptySlot, to: Empty.null)
            }.checkingDeadlock(false)
        }
    }
}
