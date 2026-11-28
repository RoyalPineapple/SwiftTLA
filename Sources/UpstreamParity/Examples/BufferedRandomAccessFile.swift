// A buffered file refines the contents and cursor of a random-access file.
// https://github.com/tlaplus/Examples/blob/ceeaa904140e3e03781cb2a79cd6c6d8b8b08e10/specifications/braf/BufferedRandomAccessFile.tla
import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct BufferedRandomAccessFileModel: Sendable {
    package enum Byte: String, CaseIterable, FiniteTLAValueDomain {
        case a = "A", b = "B", arbitrary = "ArbitrarySymbol"
        package static let finiteValues = allCases
        package static var defaultValue: Self { .arbitrary }
        package var tlaValue: TLAValue { .constant(rawValue) }
    }
    package struct FileArray: Hashable, Sendable {
        package let elems: [Byte]
    }
    private enum Step: String, CaseIterable {
        case flush = "FlushBuffer", seek = "Seek", setLength = "SetLength"
        case readByte = "Read1", writeByte = "Write1", read = "Read", write = "WriteAtMost"
    }
    package static var spec: TLASpec {
        #spec("BufferedRandomAccessFile") { scope in
            Extends(.naturals, .sequences)
            let maxOffset = scope.parameter(tlaName: "MaxOffset", as: Int.self, in: 3...3)
            let bufferSize = scope.parameter(tlaName: "BuffSz", as: Int.self, in: 2...2)
            let symbols = scope.parameter(tlaName: "Symbols", as: Set<Byte>.self, in: Set<Set<Byte>>([Set<Byte>([.a, .b])]))
            let bytes = symbols.inserting(Byte.arbitrary)
            let offsets = IntRange(0, through: maxOffset)
            let arguments = Sequences(of: bytes, lengths: IntRange(1, through: maxOffset)).mapping { elements in
                FileArray.expression(elems: elements)
            }
            let dirty = scope.sharedVar(initial: false)
            let length = scope.sharedVar(initial: 0)
            let cursor = scope.sharedVar(tlaName: "curr", initial: 0)
            let bufferStart = scope.sharedVar(tlaName: "lo", initial: 0)
            let buffer = scope.sharedVar(tlaName: "buff", initial: FileArray.expression(elems:
                SequenceMapping(length: bufferSize) { _ in Byte.arbitrary }))
            let diskPosition = scope.sharedVar(tlaName: "diskPos", initial: 0)
            let file = scope.sharedVar(tlaName: "file_content", initial: FileArray(elems: []))
            let pointer = scope.sharedVar(tlaName: "file_pointer", initial: 0)
            let inBuffer = cursor >= bufferStart && cursor < bufferStart + bufferSize
            let bufferEnd = bufferStart + bufferSize
            let flushEnd = If(length < bufferEnd, then: length, else: bufferEnd)
            let logicalLength = If(file.elems.count >= flushEnd, then: file.elems.count, else: flushEnd)
            let overlaid = FileArray.expression(elems: SequenceMapping(length: logicalLength) { i in
                If(i > bufferStart && i <= flushEnd, then: buffer.elems[i - bufferStart],
                   else: If(i <= file.elems.count, then: file.elems[i], else: Byte.arbitrary))
            })
            let logicalFile = If(length > bufferStart, then: overlaid, else: file)
            Do(Step.flush, when: dirty) {
                If(length > bufferStart) {
                    file.set(overlaid)
                    pointer.set(flushEnd)
                    diskPosition.set(pointer)
                }
                dirty.set(false)
            }
            Do(Step.seek, over: offsets) { offset in
                If(offset < bufferStart || offset >= bufferStart + bufferSize) {
                    When(!dirty)
                    bufferStart.set((offset / bufferSize) * bufferSize)
                    buffer.set(FileArray.expression(elems: SequenceMapping(length: bufferSize) { i in
                        If(bufferStart + i <= file.elems.count, then: file.elems[bufferStart + i], else: Byte.arbitrary)
                    }))
                    pointer.set(If(bufferStart + bufferSize < file.elems.count, then: bufferStart + bufferSize, else: file.elems.count))
                    diskPosition.set(pointer)
                }
                cursor.set(offset)
            }
            Do(Step.setLength, over: offsets) { newLength in
                With(offsets) { nextPointer in
                    When(file.elems.count <= newLength || pointer <= newLength || nextPointer == newLength)
                    file.set(FileArray.expression(elems: SequenceMapping(length: newLength) { i in
                        If(i <= file.elems.count, then: file.elems[i], else: Byte.arbitrary)
                    }))
                    pointer.set(nextPointer)
                    diskPosition.set(nextPointer)
                    length.set(newLength)
                    cursor.set(If(cursor > newLength, then: newLength, else: cursor))
                    buffer.set(FileArray.expression(elems: SequenceMapping(length: bufferSize) { i in
                        If(bufferStart + i <= newLength, then: buffer.elems[i], else: Byte.arbitrary)
                    }))
                }
            }
            Do(Step.readByte, over: bytes) { byte in
                When(inBuffer && cursor < length)
                When(byte == buffer.elems[cursor - bufferStart + 1])
                cursor += 1
            }
            Do(Step.writeByte, over: bytes) { byte in
                When(inBuffer && cursor + 1 <= maxOffset)
                buffer.set(FileArray.expression(elems: SequenceMapping(length: bufferSize) { i in
                    If(i == cursor - bufferStart + 1, then: byte, else: buffer.elems[i])
                }))
                cursor += 1
                dirty.set(true)
                length.set(If(length > cursor, then: length, else: cursor))
            }
            Do(Step.read, over: arguments) { data in
                When(inBuffer)
                When(data.elems.count <= length - cursor && data.elems.count <= bufferStart + bufferSize - cursor)
                When(IntRange(1, through: data.elems.count).allSatisfy { i in data.elems[i] == buffer.elems[cursor - bufferStart + i] })
                cursor += data.elems.count
            }
            Do(Step.write, over: arguments) { data in
                When(inBuffer)
                let room = bufferStart + bufferSize - cursor
                let written = If(room < data.elems.count, then: room, else: data.elems.count)
                When(cursor + written <= maxOffset)
                buffer.set(FileArray.expression(elems: SequenceMapping(length: bufferSize) { i in
                    If(i > cursor - bufferStart && i <= cursor - bufferStart + written,
                       then: data.elems[i - (cursor - bufferStart)], else: buffer.elems[i])
                }))
                dirty.set(true)
                cursor += written
                length.set(If(length > cursor, then: length, else: cursor))
            }
            Invariant("TypeOK") {
                Bool.all.contains(dirty) && offsets.contains(length) && offsets.contains(cursor) && offsets.contains(bufferStart)
                    && offsets.contains(diskPosition) && offsets.contains(pointer) && buffer.elems.count == bufferSize
                    && file.elems.count <= maxOffset && Sequences(of: bytes).contains(file.elems)
                    && Sequences(of: bytes).contains(buffer.elems)
            }
            Invariant("Inv1") { length == logicalFile.elems.count && diskPosition == pointer }
            let bufferedOffsets = IntRange(bufferStart, through: flushEnd - 1)
            Invariant("Inv3") { bufferedOffsets.allSatisfy { i in logicalFile.elems[i + 1] == buffer.elems[i - bufferStart + 1] } }
            Invariant("Inv4") { IntRange(0, through: length - 1).allSatisfy { i in
                bufferedOffsets.contains(i) || logicalFile.elems[i + 1] == If(i < file.elems.count, then: file.elems[i + 1], else: Byte.arbitrary)
            } }
            Invariant("Inv5") { dirty || bufferedOffsets.allSatisfy { i in
                buffer.elems[i - bufferStart + 1] == If(i < file.elems.count, then: file.elems[i + 1], else: Byte.arbitrary)
            } }
            let abstraction = Instance(of: RandomAccessFileModel.self) {
                Bind(\.maxOffset, projecting: maxOffset)
                Bind(\.symbols, projecting: symbols)
            }
            Refinement("Safety", instance: abstraction, behavior: .initialAndNext) {
                Map(\.content, projecting: logicalFile)
                Map(\.pointer, from: cursor)
            }
            let symbolSymmetry = Symmetry(symbols)
            Validation("BufferedFile") {
                Bind(maxOffset, to: 3)
                Bind(bufferSize, to: 2)
                Bind(symbols, to: Set<Byte>([.a, .b]))
            }.usingSymmetry(symbolSymmetry)
        }
    }
}
