import Foundation
import SwiftTLA

package enum TLCEvaluationOutputError: Error, Equatable {
    case malformed(String)
}

package struct TLCEvaluationOutput: Sendable {
    package let prints: [AssumptionPrint<CanonicalValue>]

    package init(reading url: URL) throws {
        let bytes = Array(try Data(contentsOf: url))
        let magic = Array("STLAOUT1".utf8) + [UInt8(1)]
        guard bytes.starts(with: magic) else {
            throw TLCEvaluationOutputError.malformed("header")
        }
        var offset = magic.count
        var prints: [AssumptionPrint<CanonicalValue>] = []
        while offset < bytes.count {
            let tag = bytes[offset]
            offset += 1
            switch tag {
            case 1:
                let length = try Self.readInteger(bytes, offset: &offset, width: 4)
                guard length <= UInt64(bytes.count - offset) else {
                    throw TLCEvaluationOutputError.malformed("record length")
                }
                let end = offset + Int(length)
                guard let text = String(bytes: bytes[offset..<end], encoding: .utf8) else {
                    throw TLCEvaluationOutputError.malformed("record UTF-8")
                }
                offset = end
                do {
                    prints.append(try TLCValueParser.parsePrint(text))
                } catch {
                    throw TLCEvaluationOutputError.malformed("printed TLA value")
                }
            case 2:
                let count = try Self.readInteger(bytes, offset: &offset, width: 8)
                guard count == UInt64(prints.count), offset == bytes.count else {
                    throw TLCEvaluationOutputError.malformed("completion footer")
                }
                self.prints = prints
                return
            default:
                throw TLCEvaluationOutputError.malformed("record tag")
            }
        }
        throw TLCEvaluationOutputError.malformed("missing completion footer")
    }

    private static func readInteger(_ bytes: [UInt8], offset: inout Int, width: Int) throws -> UInt64 {
        guard width <= bytes.count - offset else {
            throw TLCEvaluationOutputError.malformed("truncated integer")
        }
        var result: UInt64 = 0
        for byte in bytes[offset..<(offset + width)] {
            result = (result << 8) | UInt64(byte)
        }
        offset += width
        return result
    }
}
