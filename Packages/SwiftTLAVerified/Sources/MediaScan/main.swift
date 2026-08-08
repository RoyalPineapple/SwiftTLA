import SwiftUI
import SwiftTLAVerified
import AVFoundation

@main
struct CameraApp: App {
    @StateObject private var model = CameraModel()

    var body: some Scene {
        WindowGroup {
            VStack(spacing: 0) {
                ZStack {
                    if model.mode == .playback, let player = model.currentPlayer {
                        VideoPlayerView(player: player)
                    } else {
                        CameraPreviewView(session: model.capture.session)
                    }

                    if let image = model.snapshotImage {
                        Image(nsImage: image)
                            .resizable().scaledToFit()
                            .transition(.opacity)
                    }
                }
                .aspectRatio(4/3, contentMode: .fit)

                HStack(spacing: 12) {
                    Button(model.mode == .recording ? "Stop" : "Record") {
                        model.toggleRecording()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(model.mode == .recording ? .red : .accentColor)

                    Button("Snapshot") {
                        Task { await model.takeSnapshot() }
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.mode != .live)

                    Button("Play") {
                        model.playRecording()
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.recordedURL == nil || model.mode != .live)

                    Button("Live") {
                        model.showLive()
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.mode == .live)
                }
                .padding()
            }
            .frame(minWidth: 480, minHeight: 400)
            .task { await model.start() }
        }
    }
}

struct CameraPreviewView: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> CapturePreviewNSView {
        let view = CapturePreviewNSView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateNSView(_ nsView: CapturePreviewNSView, context: Context) {
        nsView.previewLayer.frame = nsView.bounds
    }
}

final class CapturePreviewNSView: NSView {
    let previewLayer = AVCaptureVideoPreviewLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.addSublayer(previewLayer)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        previewLayer.frame = bounds
    }
}

struct VideoPlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .none
        return view
    }
    func updateNSView(_ nsView: AVPlayerView, context: Context) {}
}

@MainActor
final class CameraModel: ObservableObject {
    let capture = Media.Capture()
    @Published var mode: Mode = .live
    @Published var snapshotImage: NSImage?
    var recordedURL: URL?
    var currentPlayer: AVPlayer?
    private var writer: Media.Writer?
    private var frameTask: Task<Void, Never>?

    enum Mode { case live, recording, playback }

    func start() async {
        guard let device = AVCaptureDevice.default(for: .video) else {
            print("No camera"); return
        }
        do {
            try capture.configure(device: device)
            try await capture.start()
        } catch {
            print("Camera error: \(error)")
        }
    }

    func takeSnapshot() async {
        do {
            let data = try await capture.capturePhoto()
            snapshotImage = NSImage(data: data)
            try? await Task.sleep(for: .seconds(1.5))
            snapshotImage = nil
        } catch {
            print("Snapshot error: \(error)")
        }
    }

    func toggleRecording() {
        Task {
            if mode == .recording {
                await stopRecording()
            } else {
                await startRecording()
            }
        }
    }

    private func startRecording() async {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("recording-\(UUID().uuidString).mov")
        let w = Media.Writer(url: url, fileType: .mov,
                             outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264])
        do {
            try await w.start()
            mode = .recording
            writer = w
            recordedURL = url
            let stream = await capture.stream()
            frameTask = Task { await w.drain(stream) }
        } catch {
            print("Record start error: \(error)")
        }
    }

    private func stopRecording() async {
        frameTask?.cancel()
        do {
            try await writer?.finish()
        } catch {
            print("Record finish error: \(error)")
        }
        writer = nil
        mode = .live
    }

    func playRecording() {
        guard let url = recordedURL else { return }
        let player = AVPlayer(url: url)
        currentPlayer = player
        mode = .playback
        player.play()

        NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime,
                                               object: player.currentItem, queue: .main) { [weak self] _ in
            self?.showLive()
        }
    }

    func showLive() {
        currentPlayer?.pause()
        currentPlayer = nil
        mode = .live
    }
}
