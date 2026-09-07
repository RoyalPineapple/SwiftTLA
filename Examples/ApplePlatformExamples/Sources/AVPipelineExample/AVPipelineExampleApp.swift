import SwiftUI
@preconcurrency import AVPipeline
import AVFoundation
import Observation
import OSLog

private let cameraLog = Logger(subsystem: "org.swifttla.examples", category: "CameraApp")

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
                        CameraPreviewView(session: effects.session)
                    }

                    if let preview = effects.selectedPhoto {
                        PhotoDetailView(data: preview) { effects.selectedPhoto = nil }
                    } else if phase == .live, effects.flashActive {
                        Rectangle().fill(.white).transition(.opacity)
                    }
                }
                .aspectRatio(4/3, contentMode: .fit)

                filmstrip
                Text("Generated state: \(phase.rawValue)")
                    .foregroundStyle(.white)
                    .padding(.vertical, 6)
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
                    effects.recordingDidFinish = { attemptID, url, error, action in
                        recordingDidFinish(attemptID: attemptID, url: url, error: error, action: action)
                    }
                    effects.playbackDidFinish = { Task { await live() } }
                    cameraLog.info("initialized camera workflow")
                    await ready()
                } catch {
                    effects.diagnostic = "Camera workflow failed to initialize: \(error)"
                    cameraLog.error("camera workflow initialization failed: \(String(describing: error), privacy: .public)")
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

                if phase == .recording {
                    Button("Cancel", action: cancelRecording)
                        .buttonStyle(.bordered)
                }

                if phase == .live {
                    Button("Demonstrate Rejection", action: demonstrateUnavailableAction)
                        .buttonStyle(.bordered)
                }
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

    private func send(_ action: CameraWorkflow.Action, attemptID: UUID? = nil) -> Bool {
        guard var machine else {
            effects.diagnostic = "Camera workflow did not initialize."
            cameraLog.error("rejected action=\(String(describing: action), privacy: .public) reason=machine-unavailable")
            return false
        }
        let before = machine.state.phase
        do {
            let transition = try machine.send(action)
            self.machine = machine
            effects.diagnostic = nil
            cameraLog.info("accepted action=\(String(describing: action), privacy: .public) attempt=\(attemptID?.uuidString ?? "none", privacy: .public) before=\(String(describing: transition.before.phase), privacy: .public) after=\(String(describing: transition.after.phase), privacy: .public)")
            return true
        } catch {
            let breadcrumb = attemptID?.uuidString ?? "none"
            let current = machine.state.phase
            effects.diagnostic = "Action \(action) rejected: \(error). State retained from \(before) to \(current). Attempt \(breadcrumb)."
            cameraLog.error("rejected action=\(String(describing: action), privacy: .public) attempt=\(breadcrumb, privacy: .public) error=\(String(describing: error), privacy: .public) before=\(String(describing: before), privacy: .public) current=\(String(describing: current), privacy: .public)")
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
            guard send(.stopRecording, attemptID: effects.activeRecordingID) else { return }
            effects.stopRecording()
        } else if isEnabled(.record) {
            guard let attemptID = effects.prepareRecordingAttempt() else { return }
            guard send(.record, attemptID: attemptID) else {
                effects.discardPreparedRecording(attemptID: attemptID)
                return
            }
            effects.startRecording(attemptID: attemptID)
        }
    }

    private func cancelRecording() {
        guard isEnabled(.stopRecording), send(.stopRecording, attemptID: effects.activeRecordingID) else { return }
        effects.cancelRecording()
    }

    private func recordingDidFinish(attemptID: UUID, url: URL, error: Error?, action: CameraWorkflow.Action) {
        guard send(action, attemptID: attemptID) else { return }
        if action == .recordingSucceeded {
            effects.recordingSucceeded(at: url)
        } else if let error {
            effects.diagnostic = "Recording attempt \(attemptID.uuidString) failed: \(error)"
        }
    }

    private func demonstrateUnavailableAction() {
        _ = send(.recordingSucceeded)
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
    private let capture = CameraCapture()
    var roll: [RollItem] = []
    var flashActive = false
    var selectedPhoto: Data?
    var recordedURL: URL?
    var currentPlayer: AVPlayer?
    private let photoDirectory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures/SwiftTLA/camera")
    private var movieOutput: AVCaptureMovieFileOutput?
    private var recordingDelegates: [UUID: RecordingDelegate] = [:]
    var diagnostic: String?
    var recordingDidFinish: ((UUID, URL, Error?, CameraWorkflow.Action) -> Void)?
    var playbackDidFinish: (() -> Void)?

    var canRecord: Bool { movieOutput != nil }
    var activeRecordingID: UUID? { recordingCallbacks.pendingAttemptID }
    var session: AVCaptureSession { capture.session }
    private var recordingCallbacks = RecordingCallbackCorrelation()

    init() {
        do {
            try FileManager.default.createDirectory(at: photoDirectory, withIntermediateDirectories: true)
        } catch {
            diagnostic = String(describing: error)
        }
    }

    func takeSnapshot() async {
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

    func prepareRecordingAttempt() -> UUID? {
        guard movieOutput != nil else {
            diagnostic = "The camera output is not ready."
            return nil
        }
        guard let attemptID = recordingCallbacks.begin() else {
            diagnostic = "A recording attempt is already active."
            return nil
        }
        cameraLog.info("prepared recording attempt=\(attemptID.uuidString, privacy: .public)")
        return attemptID
    }

    func discardPreparedRecording(attemptID: UUID) {
        recordingCallbacks.discard(attemptID: attemptID)
        recordingDelegates[attemptID] = nil
        cameraLog.info("discarded recording attempt=\(attemptID.uuidString, privacy: .public) reason=request-rejected")
    }

    func startRecording(attemptID: UUID) {
        guard let movieOutput, recordingCallbacks.pendingAttemptID == attemptID else {
            diagnostic = "The camera recording attempt is not ready."
            return
        }
        let delegate = RecordingDelegate(owner: self, attemptID: attemptID)
        recordingDelegates[attemptID] = delegate
        cameraLog.info("started recording attempt=\(attemptID.uuidString, privacy: .public)")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("recording-\(attemptID.uuidString).mov")
        movieOutput.startRecording(to: url, recordingDelegate: delegate)
    }

    func stopRecording() {
        guard let movieOutput else {
            diagnostic = "The camera output is not ready."
            return
        }
        movieOutput.stopRecording()
    }

    func cancelRecording() {
        guard let attemptID = recordingCallbacks.pendingAttemptID else {
            diagnostic = "There is no active recording to cancel."
            return
        }
        guard recordingCallbacks.requestCancellation(for: attemptID) else { return }
        stopRecording()
    }

    func playRecording(url: URL? = nil) async {
        recordedURL = url ?? recordedURL
        guard let url = recordedURL else { return }
        let player = AVPlayer(url: url)
        currentPlayer = player
        player.play()
        NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: player.currentItem, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.playbackDidFinish?()
            }
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

    fileprivate func finishedRecording(attemptID: UUID, url: URL, error: Error?) {
        guard let action = recordingCallbacks.consumeCallback(for: attemptID, error: error) else {
            let active = activeRecordingID?.uuidString ?? "none"
            diagnostic = "Ignored recording callback for attempt \(attemptID.uuidString); active attempt \(active)."
            cameraLog.error("ignored callback attempt=\(attemptID.uuidString, privacy: .public) active=\(active, privacy: .public) reason=unmatched-or-duplicate")
            return
        }
        recordingDelegates[attemptID] = nil
        cameraLog.info("classified callback attempt=\(attemptID.uuidString, privacy: .public) action=\(String(describing: action), privacy: .public)")
        recordingDidFinish?(attemptID, url, error, action)
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
        guard let device = AVCaptureDevice.default(for: .video) else {
            diagnostic = "No video capture device is available."
            return false
        }
        do {
            let output = AVCaptureMovieFileOutput()
            try await capture.configureAndStart(device: device, recordingOutput: output)
            movieOutput = output
            return true
        } catch {
            diagnostic = "Camera setup failed: \(error)"
            return false
        }
    }
}

private final class RecordingDelegate: NSObject, AVCaptureFileOutputRecordingDelegate {
    weak var owner: CameraEffects?
    private let attemptID: UUID

    init(owner: CameraEffects, attemptID: UUID) {
        self.owner = owner
        self.attemptID = attemptID
        super.init()
    }

    func fileOutput(_: AVCaptureFileOutput, didFinishRecordingTo url: URL,
                    from _: [AVCaptureConnection], error: Error?) {
        guard let owner else { return }
        Task { @MainActor in owner.finishedRecording(attemptID: attemptID, url: url, error: error) }
    }
}
