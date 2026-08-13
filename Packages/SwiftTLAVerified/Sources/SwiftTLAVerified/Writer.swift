import SwiftTLA
import SwiftTLAMacros
import AVFoundation

extension Media {

    @TLAActor
    public actor Writer {
        public static var spec: TLASpec {
            TLASpec("Writer") {
                let phase = Var("phase", 0)
            Variable(phase)

                Action("configure") { phase == 0 && phase.becomes(1) }
                Action("start") { phase == 1 && phase.becomes(2) }
                Action("write") { phase == 2 && phase.stays }
                Action("pause") { phase == 2 && phase.becomes(3) }
                Action("resume") { phase == 3 && phase.becomes(2) }
                Action("finish") { phase == 1 && phase.becomes(4) }
                Action("cancel") { (phase == 2 || phase == 3) && phase.becomes(5) }

                Invariant("validPhase") { phase >= 0 && phase <= 5 }
            }
        }

        public let writer: AVAssetWriter
        public let input: AVAssetWriterInput

        public init(url: URL, fileType: AVFileType, outputSettings: [String: Any]) {
            writer = try! AVAssetWriter(url: url, fileType: fileType)
            input = AVAssetWriterInput(mediaType: .video, outputSettings: outputSettings)
            writer.add(input)
        }

        public func start() async throws {
            guard _state.phase == 1 else { throw MediaError.notConfigured }
            writer.startWriting()
            try writer.startSession(atSourceTime: .zero)
            _start()
        }

        public func append(_ sample: CMSampleBuffer) -> Bool {
            guard _state.phase == 2 else { return false }
            return input.append(sample)
        }

        public func drain(_ stream: AsyncStream<CMSampleBuffer>) async {
            for await sample in stream {
                if !append(sample) { break }
            }
            do { try await finish() } catch { cancel() }
        }

        public func pause() { _pause() }
        public func resume() { _resume() }

        public func finish() async throws {
            guard _state.phase == 1 || _state.phase == 2 || _state.phase == 3
                else { throw MediaError.cannotFinish }
            input.markAsFinished()
            _finish()
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                writer.finishWriting { c.resume() }
            }
        }

        public func cancel() { _cancel(); writer.cancelWriting() }
    }
}
