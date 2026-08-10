import SwiftTLA
import AVFoundation

/// Coordinator: composes Capture, Writer, Player at runtime.
/// State machines verified individually by @TLAActor.
/// Cross-actor invariants verified by TLC (66 states, depth 10).
public actor MediaContract {
    public static var spec: TLASpec {
        let capture = Media.Capture.spec
        let writer = Media.Writer.spec
        let player = Media.Player.spec

        return TLASpec("MediaContract") {
            Use(spec: capture)
            Use(spec: writer)
            Use(spec: player)

            let cPhase = Var("cPhase", 0)
            let wPhase = Var("wPhase", 0)
            let pPhase = Var("pPhase", 0)

            Action("cStop")     { (cPhase == 2 || cPhase == 3) && (wPhase != 2 && wPhase != 3) && cPhase.becomes(0) }
            Action("cInterrupt") { cPhase == 2 && (wPhase != 2 && wPhase != 3) && cPhase.becomes(3) }
            Action("wStart")     { wPhase == 1 && cPhase == 2 && wPhase.becomes(2) }
            Action("pPlay")      { (pPhase == 2 || pPhase == 4) && wPhase == 4 && pPhase.becomes(3) }

            Invariant("writerRequiresCapture") { (wPhase != 2 && wPhase != 3) || (cPhase == 2) }
            Invariant("playerRequiresWriter")  { (pPhase != 3) || (wPhase == 4) }
        }
    }

    public let capture = Media.Capture()
    public let writer: Media.Writer
    public let player: Media.Player

    public init(outputURL: URL) {
        writer = Media.Writer(url: outputURL, fileType: .mp4, outputSettings: [:])
        player = Media.Player(url: outputURL)
    }
}
