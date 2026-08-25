import SwiftUI
@preconcurrency import AVPipeline
import AVFoundation
import Observation

@main
struct CameraApp: App {
    @State private var effects = CameraEffects()
    @State private var machine: CameraWorkflow?

    var body: some Scene {
        WindowGroup {
            VStack(spacing: 0) {
                ZStack {
                    if phase == .playing, let player = effects.currentPlayer {
                        VideoPlayerView(player: player)
                            .overlay(alignment: .topTrailing) {
                                Button {
                                    Task { await live() }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.title)
                                        .foregroundStyle(.white)
                                        .shadow(radius: 4)
                                }
                                .buttonStyle(.plain)
                                .padding(12)
                            }
                    } else {
                        if let capture = effects.capture {
                            CameraPreviewView(session: capture.session)
                        } else {
                            Color.black
                        }
                    }

                    if let preview = effects.selectedPhoto {
                        PhotoDetailView(data: preview) { effects.selectedPhoto = nil }
                    } else if phase == .live, effects.flashActive {
                        Rectangle().fill(.white).transition(.opacity)
                    }
                }
                .aspectRatio(4/3, contentMode: .fit)

                filmstrip
                controls
                if let diagnostic = effects.diagnostic {
                    Text(diagnostic)
                        .foregroundStyle(.red)
                        .padding(8)
                }
            }
            .background(.black)
            .frame(minWidth: 640, minHeight: 520)
            .task {
                guard machine == nil else { return }
                do {
                    machine = try CameraWorkflow.makeMachine()
                    effects.recordingDidFinish = { url, error in
                        recordingDidFinish(url: url, error: error)
                    }
                    effects.playbackDidFinish = { Task { await live() } }
                    await ready()
                } catch {
                    effects.diagnostic = "Camera workflow failed to initialize: \(error)"
                }
            }
        }
    }

    var filmstrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(effects.roll) { item in
                        let selected = effects.isSelected(item)
                        ThumbnailView(item: item, size: CGSize(width: 72, height: 54))
                            .id(item.id)
                            .onTapGesture {
                                switch item {
                                case .photo(let data): effects.selectedPhoto = data
                                case .video(let url): Task { await playRecording(url: url) }
                                }
                            }
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(selected ? .yellow : .clear, lineWidth: 2)
                            )
                            .overlay(alignment: .topTrailing) {
                                DeleteButton { effects.delete(item) }
                            }
                    }
                }
                .padding(.horizontal, 8)
            }
            .frame(height: 62)
            .background(.black.opacity(0.8))
            .onChange(of: effects.roll.count) {
                if let last = effects.roll.last {
                    proxy.scrollTo(last.id, anchor: .trailing)
                }
            }
        }
    }

    var controls: some View {
        HStack(spacing: 30) {
            if isEnabled(.live) || effects.selectedPhoto != nil {
                Button(action: {
                    effects.selectedPhoto = nil
                    if isEnabled(.live) {
                        Task { await live() }
                    }
                }) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.white)
                        .frame(width: 56, height: 56)
                        .background(Circle().fill(.white.opacity(0.15)))
                }
                .buttonStyle(.plain)
            } else {
                Button(action: {
                    Task { await effects.takeSnapshot() }
                }) {
                    ZStack {
                        Circle().stroke(.white, lineWidth: 4).frame(width: 64, height: 64)
                        Circle().fill(.white).frame(width: 52, height: 52)
                    }
                }
                .buttonStyle(.plain)
                .disabled(phase != .live)

                Button(action: toggleRecording) {
                    ZStack {
                        Circle().stroke(.red, lineWidth: 4).frame(width: 56, height: 56)
                        if phase == .recording {
                            RoundedRectangle(cornerRadius: 4).fill(.red).frame(width: 24, height: 24)
                        } else {
                            Circle().fill(.red).frame(width: 44, height: 44)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(effects.canRecord == false || (isEnabled(.record) == false && isEnabled(.stopRecording) == false))
            }
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(.black.opacity(0.8))
    }

    private var phase: CameraWorkflow.Phase { machine?.state.phase ?? .starting }

    private func isEnabled(_ action: CameraWorkflow.Action) -> Bool {
        guard let machine else { return false }
        return (try? machine.isEnabled(action)) == true
    }

    private func send(_ action: CameraWorkflow.Action) -> Bool {
        guard var machine else {
            effects.diagnostic = "Camera workflow did not initialize."
            return false
        }
        do {
            _ = try machine.send(action)
            self.machine = machine
            effects.diagnostic = nil
            return true
        } catch {
            effects.diagnostic = String(describing: error)
            return false
        }
    }

    private func ready() async {
        guard await effects.ready() else { return }
        guard send(.ready) else { return }
    }

    private func toggleRecording() {
        guard effects.canRecord else { return }
        if isEnabled(.stopRecording) {
            guard send(.stopRecording) else { return }
            effects.stopRecording()
        } else if isEnabled(.record) {
            guard send(.record) else { return }
            effects.startRecording()
        }
    }

    private func recordingDidFinish(url: URL, error: Error?) {
        if let error {
            guard send(.recordingFailed) else { return }
            effects.diagnostic = "Recording failed: \(error)"
            return
        }
        guard send(.recordingSucceeded) else { return }
        effects.recordingSucceeded(at: url)
    }

    private func playRecording(url: URL) async {
        guard isEnabled(.play), send(.play) else { return }
        await effects.playRecording(url: url)
    }

    private func live() async {
        guard isEnabled(.live), send(.live) else { return }
        effects.stopPlayback()
    }
}

struct ThumbnailView: View {
    let item: RollItem
    let size: CGSize

    var body: some View {
        Group {
            switch item {
            case .photo(let data):
                if let img = NSImage(data: data) {
                    Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                }
            case .video(let url):
                if let img = videoThumbnail(url) {
                    ZStack {
                        Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                        Image(systemName: "play.fill").font(.caption).foregroundColor(.white)
                            .shadow(radius: 2)
                    }
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .cornerRadius(4)
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(.white.opacity(0.3), lineWidth: 1))
    }

    func videoThumbnail(_ url: URL) -> NSImage? {
        let asset = AVAsset(url: url)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: size.width * 2, height: size.height * 2)
        do {
            let cg = try gen.copyCGImage(at: .zero, actualTime: nil)
            return NSImage(cgImage: cg, size: size)
        } catch {
            return nil
        }
    }
}

struct PhotoDetailView: View {
    let data: Data
    let onDismiss: () -> Void

    var body: some View {
        Color.black.opacity(0.95)
            .onTapGesture { onDismiss() }
            .overlay {
                if let img = NSImage(data: data) {
                    Image(nsImage: img).resizable().scaledToFit().padding(40)
                }
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
    required init?(coder: NSCoder) { nil }
    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer.frame = bounds
        CATransaction.commit()
    }
}

struct VideoPlayerView: NSViewRepresentable {
    let player: AVPlayer
    func makeNSView(context: Context) -> PlayerNSView { PlayerNSView(player: player) }
    func updateNSView(_ nsView: PlayerNSView, context: Context) {}
}

final class PlayerNSView: NSView {
    init(player: AVPlayer) {
        super.init(frame: .zero)
        wantsLayer = true
        let l = AVPlayerLayer()
        l.player = player
        l.videoGravity = .resizeAspectFill
        layer?.addSublayer(l)
    }
    required init?(coder: NSCoder) { nil }
    override func layout() {
        super.layout()
        (layer?.sublayers?.first as? AVPlayerLayer)?.frame = bounds
    }
}

struct DeleteButton: View {
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(.white)
                .background(Circle().fill(.black.opacity(0.6)).frame(width: 16, height: 16))
        }
        .buttonStyle(.plain)
        .opacity(hovered ? 1 : 0)
        .onHover { hovered = $0 }
    }
}

enum RollItem: Identifiable {
    case photo(Data)
    case video(URL)
    var id: String {
        switch self {
        case .photo(let data): return "p-\(data.hashValue)"
        case .video(let url): return "v-\(url.absoluteString)"
        }
    }
}

@MainActor
@Observable
final class CameraEffects {
    private(set) var capture: Media.Capture?
    var roll: [RollItem] = []
    var flashActive = false
    var selectedPhoto: Data?
    var recordedURL: URL?
    var currentPlayer: AVPlayer?
    private let photoDirectory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures/SwiftTLA/camera")
    private var movieOutput: AVCaptureMovieFileOutput?
    private let recordDelegate = RecordingDelegate()
    var diagnostic: String?
    var recordingDidFinish: ((URL, Error?) -> Void)?
    var playbackDidFinish: (() -> Void)?

    var canRecord: Bool { movieOutput != nil }

    init() {
        do {
            capture = try Media.Capture()
            try FileManager.default.createDirectory(at: photoDirectory, withIntermediateDirectories: true)
            recordDelegate.owner = self
        } catch {
            diagnostic = String(describing: error)
        }
    }

    func takeSnapshot() async {
        guard let capture else {
            diagnostic = "The camera did not initialize."
            return
        }
        do {
            let data = try await capture.capturePhoto()
            let name = "snap-\(Int(Date().timeIntervalSince1970)).jpg"
            try data.write(to: photoDirectory.appendingPathComponent(name))
            roll.append(.photo(data))
            flashActive = true
            try await Task.sleep(for: .milliseconds(120))
            flashActive = false
        } catch {
            diagnostic = "Snapshot failed: \(error)"
        }
    }

    func startRecording() {
        guard let movieOutput else {
            diagnostic = "The camera output is not ready."
            return
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("recording-\(UUID().uuidString).mov")
        movieOutput.startRecording(to: url, recordingDelegate: recordDelegate)
    }

    func stopRecording() {
        guard let movieOutput else {
            diagnostic = "The camera output is not ready."
            return
        }
        movieOutput.stopRecording()
    }

    func playRecording(url: URL? = nil) async {
        recordedURL = url ?? recordedURL
        guard let url = recordedURL else { return }
        let player = AVPlayer(url: url)
        currentPlayer = player
        player.play()
        NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: player.currentItem, queue: .main) { [weak self] _ in
            self?.playbackDidFinish?()
        }
    }

    func stopPlayback() {
        currentPlayer?.pause()
        currentPlayer = nil
    }

    func delete(_ item: RollItem) {
        if case .video(let url) = item {
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                diagnostic = "Recording could not be deleted: \(error)"
                return
            }
        }
        roll.removeAll { $0.id == item.id }
    }

    fileprivate func finishedRecording(url: URL, error: Error?) {
        recordingDidFinish?(url, error)
    }

    func recordingSucceeded(at url: URL) {
        recordedURL = url
        roll.append(.video(url))
    }

    func isSelected(_ item: RollItem) -> Bool {
        switch item {
        case .photo(let data):
            return selectedPhoto.map { $0 == data } ?? false
        case .video(let url):
            return recordedURL.map { $0 == url } ?? false
        }
    }
    func ready() async -> Bool {
        guard let capture,
              let device = AVCaptureDevice.default(for: .video) else {
            diagnostic = "No video capture device is available."
            return false
        }
        do {
            try await capture.configure(device: device)
            let output = AVCaptureMovieFileOutput()
            capture.session.addOutput(output)
            movieOutput = output
            try await capture.start()
            return true
        } catch {
            diagnostic = "Camera setup failed: \(error)"
            return false
        }
    }
}

private final class RecordingDelegate: NSObject, AVCaptureFileOutputRecordingDelegate {
    weak var owner: CameraEffects?

    func fileOutput(_: AVCaptureFileOutput, didFinishRecordingTo url: URL,
                    from _: [AVCaptureConnection], error: Error?) {
        guard let owner else { return }
        Task { @MainActor in owner.finishedRecording(url: url, error: error) }
    }
}
