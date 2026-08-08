import SwiftTLA
import SwiftTLAMacros
import AVFoundation

extension Media {

    @TLAActor @MainActor
    public actor Player {
        public static var spec: TLASpec {
            TLASpec("Player") {
                let phase = Var<Int>("phase")
                Variable(phase, 0)

                Action("_load")     { phase == 0 && phase.becomes(1) }
                Action("_ready")    { phase == 1 && phase.becomes(2) }
                Action("_play")     { (phase == 2 || phase == 4) && phase.becomes(3) }
                Action("_pause")    { phase == 3 && phase.becomes(4) }
                Action("_seek")     { (phase == 2 || phase == 3 || phase == 4) && phase.stays }
                Action("_finish")   { phase == 3 && phase.becomes(5) }

                Invariant("validPhase") { phase >= 0 && phase <= 5 }
            }
        }

        public let player: AVPlayer

        public init(url: URL) {
            player = AVPlayer(url: url)
        }

        public func load() async throws {
            guard _state.phase == 0 else { throw MediaError.alreadyLoaded }
            _load()
            _ = try await player.currentItem?.asset.load(.isPlayable)
            _ready()
        }

        public func play() {
            guard _state.phase == 2 || _state.phase == 4 else { return }
            _play()
            player.play()
        }

        public func pause() {
            guard _state.phase == 3 else { return }
            _pause()
            player.pause()
        }

        public func seek(to time: CMTime) {
            guard _state.phase != 1 else { return }
            _seek()
            player.seek(to: time)
        }
    }
}

