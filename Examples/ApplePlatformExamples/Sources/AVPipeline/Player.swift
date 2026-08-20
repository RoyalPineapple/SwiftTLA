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
    private enum BeginLoadProcess: String, FiniteDomainKey { case beginLoadEvent; static let formalDomain: [Self] = [.beginLoadEvent]; static let formalTypeIdentity = FormalTypeIdentity(rawValue: "apple.av.player.begin-load"); var tlaValue: TLAValue { .string(rawValue) } }
    private enum ReadyProcess: String, FiniteDomainKey { case readyEvent; static let formalDomain: [Self] = [.readyEvent]; static let formalTypeIdentity = FormalTypeIdentity(rawValue: "apple.av.player.ready"); var tlaValue: TLAValue { .string(rawValue) } }
    private enum PlayProcess: String, FiniteDomainKey { case playEvent; static let formalDomain: [Self] = [.playEvent]; static let formalTypeIdentity = FormalTypeIdentity(rawValue: "apple.av.player.play"); var tlaValue: TLAValue { .string(rawValue) } }
    private enum PauseProcess: String, FiniteDomainKey { case pauseEvent; static let formalDomain: [Self] = [.pauseEvent]; static let formalTypeIdentity = FormalTypeIdentity(rawValue: "apple.av.player.pause"); var tlaValue: TLAValue { .string(rawValue) } }
    private enum SeekProcess: String, FiniteDomainKey { case seekEvent; static let formalDomain: [Self] = [.seekEvent]; static let formalTypeIdentity = FormalTypeIdentity(rawValue: "apple.av.player.seek"); var tlaValue: TLAValue { .string(rawValue) } }
    private enum FinishProcess: String, FiniteDomainKey { case finishEvent; static let formalDomain: [Self] = [.finishEvent]; static let formalTypeIdentity = FormalTypeIdentity(rawValue: "apple.av.player.finish"); var tlaValue: TLAValue { .string(rawValue) } }
    private enum Step: String, PlusCalLabel { case beginLoad, ready, play, pause, seek, finish }
    public static var spec: TLASpec {
        #spec("PlayerModel") {
            Algorithm("PlayerModel") {
                let phase = SharedVar(initial: Phase.unloaded)
                Each(BeginLoadProcess.all) { _ in Do(Step.beginLoad) { When(phase == .unloaded); Assign(phase, to: Phase.loading); Goto(Step.beginLoad) } }
                Each(ReadyProcess.all) { _ in Do(Step.ready) { When(phase == .loading); Assign(phase, to: Phase.ready); Goto(Step.ready) } }
                Each(PlayProcess.all) { _ in Do(Step.play) { When(phase == .ready || phase == .paused); Assign(phase, to: Phase.playing); Goto(Step.play) } }
                Each(PauseProcess.all) { _ in Do(Step.pause) { When(phase == .playing); Assign(phase, to: Phase.paused); Goto(Step.pause) } }
                Each(SeekProcess.all) { _ in Do(Step.seek) { When(phase == .ready || phase == .playing || phase == .paused); Assign(phase, to: phase); Goto(Step.seek) } }
                Each(FinishProcess.all) { _ in Do(Step.finish) { When(phase == .playing); Assign(phase, to: Phase.finished); Goto(Step.finish) } }
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
            _ = try await machine.apply(.beginLoad)
            _ = try await player.currentItem?.asset.load(.isPlayable)
            _ = try await machine.apply(.ready)
        }
        public func play() async {
            let phase = await machine.state.phase
            guard phase == .ready || phase == .paused else { return }
            _ = try? await machine.apply(.play)
            player.play()
        }
        public func pause() async { guard await machine.state.phase == .playing else { return }; _ = try? await machine.apply(.pause); player.pause() }
        public func seek(to time: CMTime) async { guard await machine.state.phase != .loading else { return }; _ = try? await machine.apply(.seek); await player.seek(to: time) }
    }
}
