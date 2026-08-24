import AVFoundation
import SwiftTLA
import SwiftTLAMacros

@TLAModel
public struct PlayerModel {
    public enum Phase: String, CaseIterable, FiniteTLAValueDomain {
        case unloaded, loading, ready, playing, paused, finished
        public static var defaultValue: Self { .unloaded }
        public static let finiteValues = allCases
        public var tlaValue: TLAValue { .string(rawValue) }
    }
    private enum BeginLoadProcess: String, FiniteTLAValueDomain { case beginLoadEvent; static var defaultValue: Self { .beginLoadEvent }; static let finiteValues: [Self] = [.beginLoadEvent]; var tlaValue: TLAValue { .string(rawValue) } }
    private enum ReadyProcess: String, FiniteTLAValueDomain { case readyEvent; static var defaultValue: Self { .readyEvent }; static let finiteValues: [Self] = [.readyEvent]; var tlaValue: TLAValue { .string(rawValue) } }
    private enum PlayProcess: String, FiniteTLAValueDomain { case playEvent; static var defaultValue: Self { .playEvent }; static let finiteValues: [Self] = [.playEvent]; var tlaValue: TLAValue { .string(rawValue) } }
    private enum PauseProcess: String, FiniteTLAValueDomain { case pauseEvent; static var defaultValue: Self { .pauseEvent }; static let finiteValues: [Self] = [.pauseEvent]; var tlaValue: TLAValue { .string(rawValue) } }
    private enum SeekProcess: String, FiniteTLAValueDomain { case seekEvent; static var defaultValue: Self { .seekEvent }; static let finiteValues: [Self] = [.seekEvent]; var tlaValue: TLAValue { .string(rawValue) } }
    private enum FinishProcess: String, FiniteTLAValueDomain { case finishEvent; static var defaultValue: Self { .finishEvent }; static let finiteValues: [Self] = [.finishEvent]; var tlaValue: TLAValue { .string(rawValue) } }
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
}

extension Media {
    public actor Player {
        private var machine: PlayerModel
        public let player: AVPlayer

        public init(url: URL) throws {
            machine = try PlayerModel.makeMachine()
            player = AVPlayer(url: url)
        }

        public func phase() async -> PlayerModel.Phase { machine.state.phase }

        public func load() async throws {
            guard try machine.isEnabled(.beginLoad) else { throw MediaError.alreadyLoaded }
            _ = try await player.currentItem?.asset.load(.isPlayable)
            _ = try machine.send(.beginLoad)
            _ = try machine.send(.ready)
        }

        public func play() async throws {
            _ = try machine.send(.play)
            player.play()
        }

        public func pause() async throws {
            _ = try machine.send(.pause)
            player.pause()
        }

        public func seek(to time: CMTime) async throws {
            _ = try machine.send(.seek)
            await player.seek(to: time)
        }
    }
}
