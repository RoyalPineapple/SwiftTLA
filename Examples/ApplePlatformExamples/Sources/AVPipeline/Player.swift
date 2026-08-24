import AVFoundation
import SwiftTLA
import SwiftTLAMacros

@TLAModel
public struct PlayerModel {
    public enum Phase: String, CaseIterable {
        case unloaded, loading, ready, playing, paused, finished
    }
    private enum BeginLoadProcess: String, CaseIterable { case beginLoadEvent }
    private enum ReadyProcess: String, CaseIterable { case readyEvent }
    private enum PlayProcess: String, CaseIterable { case playEvent }
    private enum PauseProcess: String, CaseIterable { case pauseEvent }
    private enum SeekProcess: String, CaseIterable { case seekEvent }
    private enum FinishProcess: String, CaseIterable { case finishEvent }
    private enum Step: String, CaseIterable { case beginLoad, ready, play, pause, seek, finish }
    public static var spec: TLASpec {
        #spec("PlayerModel") {
            Algorithm("PlayerModel", scoped: { scope in
                let phase = scope.sharedVar("phase", initial: Phase.unloaded)
                Each(BeginLoadProcess.all) { _ in Do(Step.beginLoad) { When(phase == .unloaded); Assign(phase, to: Phase.loading); Goto(Step.beginLoad) } }
                Each(ReadyProcess.all) { _ in Do(Step.ready) { When(phase == .loading); Assign(phase, to: Phase.ready); Goto(Step.ready) } }
                Each(PlayProcess.all) { _ in Do(Step.play) { When(phase == .ready || phase == .paused); Assign(phase, to: Phase.playing); Goto(Step.play) } }
                Each(PauseProcess.all) { _ in Do(Step.pause) { When(phase == .playing); Assign(phase, to: Phase.paused); Goto(Step.pause) } }
                Each(SeekProcess.all) { _ in Do(Step.seek) { When(phase == .ready || phase == .playing || phase == .paused); Assign(phase, to: phase); Goto(Step.seek) } }
                Each(FinishProcess.all) { _ in Do(Step.finish) { When(phase == .playing); Assign(phase, to: Phase.finished); Goto(Step.finish) } }
                Invariant("knownPlayerPhase") { phase == .unloaded || phase == .loading || phase == .ready || phase == .playing || phase == .paused || phase == .finished }
            })
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
            _ = try await machine.send(.beginLoad)
            _ = try await player.currentItem?.asset.load(.isPlayable)
            _ = try await machine.send(.ready)
        }
        public func play() async {
            let phase = await machine.state.phase
            guard phase == .ready || phase == .paused else { return }
            _ = try? await machine.send(.play)
            player.play()
        }
        public func pause() async { guard await machine.state.phase == .playing else { return }; _ = try? await machine.send(.pause); player.pause() }
        public func seek(to time: CMTime) async { guard await machine.state.phase != .loading else { return }; _ = try? await machine.send(.seek); await player.seek(to: time) }
    }
}
