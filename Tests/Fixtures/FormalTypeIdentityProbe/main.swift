import SwiftTLA

private struct FilePrivateShape: FormalValue {
    static let formalTypeIdentity = FormalTypeIdentity(rawValue: "example.file-private-shape-v1")

    var tlaValue: TLAValue { .record([:]) }
}

print(FormalTypeIdentity.of(FilePrivateShape.self).rawValue)
