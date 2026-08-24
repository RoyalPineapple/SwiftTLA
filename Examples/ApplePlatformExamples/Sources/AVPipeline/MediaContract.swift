import AVFoundation
import SwiftTLA
import SwiftTLAMacros

/// The pipeline contract is a generated model. Capture, writing, and playback
/// are explicit formal stages; AVFoundation remains a thin effect layer.
@TLAModel
public struct MediaPipelineModel {
    public enum Stage: String, CaseIterable {
        case idle, capturing, writing, readyToPlay, playing
    public let writer: Media.Writer
    public let player: Media.Player
    public init(outputURL: URL) throws {
        writer = try Media.Writer(url: outputURL, fileType: .mp4, outputSettings: [:])
        player = Media.Player(url: outputURL)
    }
    public func stage() async -> MediaPipelineModel.Stage { await machine.state.stage }
}
