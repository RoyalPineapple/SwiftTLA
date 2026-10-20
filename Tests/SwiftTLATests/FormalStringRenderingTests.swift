import Testing
@testable import SwiftTLA

struct FormalStringRenderingTests {
    @Test("TLA string literals escape ASCII syntax and encode Unicode reversibly")
    func escapedLiterals() throws {
        let ascii = "quote\" slash\\ newline\n return\r tab\t form\u{c}"
        let escapedASCII = #""quote\" slash\\ newline\n return\r tab\t form\f""#
        #expect(TLAValue.string(ascii).description == escapedASCII)
        let encodedUnicode = #""__SwiftTLA_UTF8_V1__C3A9""#
        #expect(TLAValue.string("é").description == encodedUnicode)
        #expect(TLAValue.string("e\u{301}").description == #""__SwiftTLA_UTF8_V1__65CC81""#)
        #expect(TLAValue.tuple([.string("é")]).description == "<<\(encodedUnicode)>>")
        #expect(TLAValue.function([.string("é"): .string("é")]).description
            == "[__tla_fn_0 \\in {\(encodedUnicode)} |-> \(encodedUnicode)]")

        let text = Var<String>("text")
        let note = Var<String>("note")
        let specification = TLASpec("EscapedStrings") {
            Variable(text, "e\u{301}")
            Variable(note, "\\* SwiftTLA formal strings: utf8-v1")
        }
        let rendered = try specification.compile().render().tlaBundle.tla
        #expect(rendered.contains("text = \(encodedUnicode)"))
        #expect(!rendered.contains("é"))
        #expect(rendered.split(separator: "\n").dropFirst().first == Substring(FormalStringEncoding.declaration))
    }

    @Test("formal string encoding preserves exact bytes and cannot alias an ASCII marker")
    func encodedStringRoundTrips() throws {
        let samples = ["plain", "é", "e\u{301}", "🐈", FormalStringEncoding.prefix,
            FormalStringEncoding.prefix + "C3A9"]
        for sample in samples {
            let encoded = FormalStringEncoding.encode(sample)
            #expect(encoded.utf8.allSatisfy { $0 < 128 })
            #expect(FormalStringEncoding.decode(encoded)?.utf8.elementsEqual(sample.utf8) == true)
        }
        #expect(FormalStringEncoding.encode("é") != FormalStringEncoding.encode("e\u{301}"))
        #expect(FormalStringEncoding.decode(FormalStringEncoding.prefix + "C3A") == nil)
        #expect(FormalStringEncoding.decode(FormalStringEncoding.prefix + "C3A9ff") == nil)
        #expect(FormalStringEncoding.decode(FormalStringEncoding.prefix + "c3a9") == nil)

        func standardHex(_ value: String) -> String {
            FormalStringEncoding.prefix + value.utf8.map { byte in
                let digits = String(byte, radix: 16, uppercase: true)
                return digits.count == 1 ? "0" + digits : digits
            }.joined()
        }
        for scalar in Array(0...127) + Array(0x80...0xBF) + [0x7FF, 0x800, 0x10FFFF] {
            let value = FormalStringEncoding.prefix + String(try #require(UnicodeScalar(scalar)))
            #expect(FormalStringEncoding.encode(value) == standardHex(value))
        }
    }

    @Test("typed Swift strings have one formal value for canonical equivalents")
    func typedStringIdentity() throws {
        let composed = "\u{00E9}"
        let decomposed = "e\u{301}"
        #expect(composed == decomposed)
        #expect(composed.tlaValue == decomposed.tlaValue)
        #expect(Set([composed.tlaValue, decomposed.tlaValue]).count == 1)
        guard case .string(let encoded) = decomposed.tlaValue else {
            Issue.record("Expected a formal string")
            return
        }
        #expect(encoded.utf8.elementsEqual(composed.utf8))
        let decodedRawFormal = try #require(String(formalValue: .string(decomposed)))
        #expect(decodedRawFormal.utf8.elementsEqual(decomposed.utf8))
    }
}
