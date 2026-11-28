// The abstract file used by BufferedRandomAccessFile's refinement. Offsets start at zero.
// https://github.com/tlaplus/Examples/blob/ceeaa904140e3e03781cb2a79cd6c6d8b8b08e10/specifications/braf/BufferedRandomAccessFile.tla
import SwiftTLA
import SwiftTLAMacros

@TLAModel
package struct RandomAccessFileModel: Sendable {
    package enum Byte: String, CaseIterable, FiniteTLAValueDomain {
        case a = "A", b = "B", arbitrary = "ArbitrarySymbol"
        package static let finiteValues = allCases
        package static var defaultValue: Self { .arbitrary }
        package var tlaValue: TLAValue { .constant(rawValue) }
    }
    package struct FileArray: Hashable, Sendable {
        package let elems: [Byte]
    }
    private enum Step: String, CaseIterable { case seek = "Seek", setLength = "SetLength", read = "Read", write = "Write" }

    package static var spec: TLASpec {
        #spec("RandomAccessFile") { scope in
            Extends(.naturals, .sequences)
            let maxOffset = scope.parameter(tlaName: "MaxOffset", as: Int.self, in: 3...3)
            let symbols = scope.parameter(tlaName: "Symbols", as: Set<Byte>.self, in: Set<Set<Byte>>([Set<Byte>([.a, .b])]))
            let bytes = symbols.inserting(Byte.arbitrary)
            let offsets = IntRange(0, through: maxOffset)
            let arguments = Sequences(of: bytes, lengths: IntRange(1, through: maxOffset)).mapping { elements in
                FileArray.expression(elems: elements)
            }
            let content = scope.sharedVar(tlaName: "file_content", initial: FileArray(elems: []))
            let pointer = scope.sharedVar(tlaName: "file_pointer", initial: 0)

            Do(Step.seek, over: offsets) { offset in
                pointer.set(offset)
            }
            Do(Step.setLength, over: offsets) { length in
                // Truncating past the cursor fixes it at EOF. The published spec permits any offset otherwise.
                With(offsets) { nextPointer in
                    When(content.elems.count <= length || pointer <= length || nextPointer == length)
                    content.set(FileArray.expression(elems: SequenceMapping(length: length) { i in
                        If(i <= content.elems.count, then: content.elems[i], else: Byte.arbitrary)
                    }))
                    pointer.set(nextPointer)
                }
            }
            Do(Step.read, over: arguments) { data in
                When(pointer + data.elems.count <= content.elems.count)
                When(IntRange(1, through: data.elems.count).allSatisfy { i in
                    data.elems[i] == content.elems[pointer + i]
                })
                pointer.set(pointer + data.elems.count)
            }
            Do(Step.write, over: arguments) { data in
                When(pointer + data.elems.count <= maxOffset)
                let end = pointer + data.elems.count
                let length = If(content.elems.count >= end, then: content.elems.count, else: end)
                content.set(FileArray.expression(elems: SequenceMapping(length: length) { i in
                    If(i > pointer && i <= end, then: data.elems[i - pointer],
                       else: If(i <= content.elems.count, then: content.elems[i], else: Byte.arbitrary))
                }))
                pointer.set(pointer + data.elems.count)
            }
            Invariant("TypeOK") {
                Sequences(of: bytes).contains(content.elems) && content.elems.count <= maxOffset && offsets.contains(pointer)
            }
            Validation("FileContract") {
                Bind(maxOffset, to: 3)
                Bind(symbols, to: Set<Byte>([.a, .b]))
            }
        }
    }
}
