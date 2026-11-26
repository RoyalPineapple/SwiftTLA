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
            let Writers = scope.parameter(as: Set<ThreadID>.self, in: Subsets(of: Set<ThreadID>([ThreadID.w1, ThreadID.w2])))
            let Readers = scope.parameter(as: Set<ThreadID>.self, in: Subsets(of: Set<ThreadID>([ThreadID.r1, ThreadID.r2, ThreadID.r3])))
            let Size = scope.parameter(as: Int.self, in: Int.all)
            let MaxPublished = scope.parameter(as: Int.self, in: Int.all)
            let NULL = scope.parameter(as: Empty.self, in: Set<Empty>([Empty.null]))
            Assume(!Writers.isEmpty && !Readers.isEmpty && Writers.intersection(Readers).isEmpty)
            Assume(Size > 0 && MaxPublished > 0)
            let threads = Writers.union(Readers)
            let indices = IntRange(0, through: Size - 1)
            let emptyAccess = Dictionary<Int, Set<ThreadID>>.mapping(over: indices) { _ in Set<ThreadID>() }
            let ringbuffer = scope.sharedVar(initial: Buffer.expression(
                slots: Dictionary<Int, Slot>.mapping(over: indices) { _ in Slot.second(NULL) },
                readers: emptyAccess, writers: emptyAccess))
            let next_sequence = scope.sharedVar(initial: 0)
            let claimed_sequence = scope.sharedVar(initial: Dictionary<ThreadID, Int>.mapping(over: Writers) { _ in -1 })
            let published = scope.sharedVar(initial: Dictionary<Int, Bool>.mapping(over: indices) { _ in false })
            let read = scope.sharedVar(initial: Dictionary<ThreadID, Int>.mapping(over: Readers) { _ in -1 })
            let consumed = scope.sharedVar(initial: Dictionary<ThreadID, [Int]>.mapping(over: Readers) { _ in [Int]() })
            let pc = scope.sharedVar(initial: Dictionary<ThreadID, String>.mapping(over: threads) { _ in "Advance" })

            Do(Step.beginWrite, over: Writers) { writer in
                let next = next_sequence
                let index = next % Size
                When(Readers.allSatisfy { r in read[r] >= next - Size })
                When(pc[writer] == "Advance")
                claimed_sequence[writer].set(next)
                pc[writer].set("Access")
                ringbuffer.writers[index].insert(writer)
                ringbuffer.slots[index].set(Slot.first(next))
                next_sequence.set(next + 1)
            }
            Do(Step.endWrite, over: Writers) { writer in
                let next = claimed_sequence[writer]
                When(pc[writer] == "Access")
                pc[writer].set("Advance")
                ringbuffer.writers[next % Size].remove(writer)
                published[next % Size].set(!published[next % Size])
            }
            let beginRead = Do(Step.beginRead, over: Readers) { reader in
                let next = read[reader] + 1
                let index = next % Size
                When(pc[reader] == "Advance" && published[index] == ((next / Size) % 2 == 0))
                pc[reader].set("Access")
                ringbuffer.readers[index].insert(reader)
                consumed[reader].set(consumed[reader].appending(ringbuffer.slots[index].assuming(Int.self)))
            }
            let endRead = Do(Step.endRead, over: Readers) { reader in
                let next = read[reader] + 1
                When(pc[reader] == "Access")
                pc[reader].set("Advance")
                ringbuffer.readers[next % Size].remove(reader)
                read[reader].set(next)
            }
            WeakFairness(each: beginRead)
            WeakFairness(each: endRead)
            Constraint(next_sequence <= MaxPublished)
            let NoDataRaces = Invariant()
            NoDataRaces {
                indices.allSatisfy { i in
                    (ringbuffer.readers[i].isEmpty || ringbuffer.writers[i].isEmpty) && ringbuffer.writers[i].count <= 1
                }
            }
            let TypeOk = Invariant()
            TypeOk {
                ringbuffer.slots.keys == indices && ringbuffer.readers.keys == indices && ringbuffer.writers.keys == indices
                indices.allSatisfy { i in
                    (ringbuffer.slots[i] == Slot.second(NULL) || Int.all.contains(ringbuffer.slots[i].assuming(Int.self))) &&
                    ringbuffer.readers[i].isSubset(of: Readers) && ringbuffer.writers[i].isSubset(of: Writers)
                }
                next_sequence >= 0 && Functions(from: Writers, to: Int.all).contains(claimed_sequence)
                Functions(from: indices, to: Bool.all).contains(published)
                Functions(from: Readers, to: Int.all).contains(read)
                Functions(from: threads, to: Set<String>(["Advance", "Access"])).contains(pc)
                consumed.keys == Readers && Readers.allSatisfy { r in
                    IntRange(1, through: consumed[r].count).allSatisfy { i in consumed[r][i] >= 0 }
                }
            }
            let subjects = Readers.flatMapping { r in IntRange(0, through: MaxPublished - 1).mapping { i in
                ReadPosition.expression(reader: r, sequence: i)
            } }
            let claimed = Writers.mapping { w in claimed_sequence[w] }
            let minimum = Select(from: claimed) { n in Writers.allSatisfy { w in n <= claimed_sequence[w] } }
            let available = Select(from: claimed.inserting(minimum - 1)) { n in
                published[n % Size] != ((n / Size) % 2 == 0) || !Writers.contains { w in
                    claimed_sequence[w] == n + 1 && published[claimed_sequence[w] % Size] == ((claimed_sequence[w] / Size) % 2 == 0)
                }
            }
            let Liveliness = Temporal()
            Liveliness(forEach: subjects) { pair in
                .eventuallyAlways(pair.sequence > available || (consumed[pair.reader].count >= pair.sequence + 1 &&
                    consumed[pair.reader][pair.sequence + 1] == pair.sequence))
            }
            Validation("Upstream") {
                Bind(Writers, to: Set<ThreadID>([ThreadID.w1, ThreadID.w2]))
                Bind(Readers, to: Set<ThreadID>([ThreadID.r1, ThreadID.r2, ThreadID.r3]))
                Bind(Size, to: 4)
                Bind(MaxPublished, to: 10)
                Bind(NULL, to: Empty.null)
            }.checking(only: [TypeOk, NoDataRaces]).checkingDeadlock(false)
            Validation("LivelinessCheck") {
                Bind(Writers, to: Set<ThreadID>([ThreadID.w1, ThreadID.w2]))
                Bind(Readers, to: Set<ThreadID>([ThreadID.r1, ThreadID.r2]))
                Bind(Size, to: 4)
                Bind(MaxPublished, to: 10)
                Bind(NULL, to: Empty.null)
            }.checkingDeadlock(false)
        }
    }
}
