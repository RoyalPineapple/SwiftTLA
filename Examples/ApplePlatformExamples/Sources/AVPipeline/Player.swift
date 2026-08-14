import AVFoundation
import SwiftTLA
import SwiftTLAMacros

@TLAModel
public struct PlayerModel {
    public enum Phase: String, CaseIterable, FiniteDomainKey {
        case unloaded, loading, ready, playing, paused, finished
        public static let formalDomain = allCases
        public static let formalTypeIdentity = FormalTypeIdentity(rawValue: "apple.av.player-phase")
        public var tlaValue: TLAValue { .string(rawValue) }
    }
    private enum Process: String, FiniteDomainKey { case playerEvent
        static let formalDomain: [Self] = [.playerEvent]
        static let formalTypeIdentity = FormalTypeIdentity(rawValue: "apple.av.player-process")
        var tlaValue: TLAValue { .string(rawValue) }
    }
    private enum Step: String, PlusCalLabel { case beginLoad, ready, play, pause, seek, finish }
    public static var spec: TLASpec {
        #spec("PlayerModel") {
            Algorithm("PlayerModel") {
                let phase = SharedVar(initial: Phase.unloaded)
                Each(Process.all) { _ in
                    Do(Step.beginLoad) { When(phase == .unloaded); Assign(phase, to: Phase.loading); Goto(Step.beginLoad) }
                    Do(Step.ready) { When(phase == .loading); Assign(phase, to: Phase.ready); Goto(Step.ready) }
                    Do(Step.play) { When(phase == .ready || phase == .paused); Assign(phase, to: Phase.playing); Goto(Step.play) }
                    Do(Step.pause) { When(phase == .playing); Assign(phase, to: Phase.paused); Goto(Step.pause) }
                    Do(Step.seek) { When(phase == .ready || phase == .playing || phase == .paused); Assign(phase, to: phase); Goto(Step.seek) }
                    Do(Step.finish) { When(phase == .playing); Assign(phase, to: Phase.finished); Goto(Step.finish) }
                }
                Invariant("knownPlayerPhase") { phase == .unloaded || phase == .loading || phase == .ready || phase == .playing || phase == .paused || phase == .finished }
            }
        }
    }
    @TLAActor public actor Machine {}
}

extension Media {
    public actor Player {
        private let machine = PlayerModel.Machine()
        public let player: AVPlayer
        public init(url: URL) { player = AVPlayer(url: url) }
        public func phase() async -> PlayerModel.Phase { await machine.state.phase }
        public func load() async throws {
            guard await machine.state.phase == .unloaded else { throw MediaError.alreadyLoaded }
            _ = try await machine.execute(PlayerModel.Machine.ActionLabel.beginLoad.toInvocation())
            _ = try await player.currentItem?.asset.load(.isPlayable)
            _ = try await machine.execute(PlayerModel.Machine.ActionLabel.ready.toInvocation())
        }
        public func play() async {
            let phase = await machine.state.phase
            guard phase == .ready || phase == .paused else { return }
            _ = try? await machine.execute(PlayerModel.Machine.ActionLabel.play.toInvocation())
            player.play()
        }
        public func pause() async { guard await machine.state.phase == .playing else { return }; _ = try? await machine.execute(PlayerModel.Machine.ActionLabel.pause.toInvocation()); player.pause() }
        public func seek(to time: CMTime) async { guard await machine.state.phase != .loading else { return }; _ = try? await machine.execute(PlayerModel.Machine.ActionLabel.seek.toInvocation()); await player.seek(to: time) }
    }
}
