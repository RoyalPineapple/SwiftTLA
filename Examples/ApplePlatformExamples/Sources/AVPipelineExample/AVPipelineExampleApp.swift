import SwiftUI
@preconcurrency import AVPipeline
import SwiftTLA
import SwiftTLAMacros
import AVFoundation
import Observation

@main
struct CameraApp: App {
    @State private var controller = CameraController()

    var body: some Scene {
        WindowGroup {
            VStack(spacing: 0) {
                ZStack {
                    if controller.phase == .playing, let player = controller.currentPlayer {
                        VideoPlayerView(player: player)
                            .overlay(alignment: .topTrailing) {
                                Button {
                                    controller.currentPlayer?.pause()
                                    controller.currentPlayer = nil
                                    Task { await controller.live() }
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
                        if let capture = controller.capture {
                            CameraPreviewView(session: capture.session)
                        } else {
                            Color.black
                        }
                    }

                    if let preview = controller.selectedPhoto {
                        PhotoDetailView(data: preview) { controller.selectedPhoto = nil }
                    } else if controller.phase == .live, controller.flashActive {
                        Rectangle().fill(.white).transition(.opacity)
                    }
                }
                .aspectRatio(4/3, contentMode: .fit)

                filmstrip
                controls
                if let diagnostic = controller.diagnostic {
                    Text(diagnostic)
                        .foregroundStyle(.red)
                        .padding(8)
                }
            }
            .background(.black)
            .frame(minWidth: 640, minHeight: 520)
            .task { await controller.ready() }
        }
    }

    var filmstrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(controller.roll) { item in
                        let selected = controller.isSelected(item)
                        ThumbnailView(item: item, size: CGSize(width: 72, height: 54))
                            .id(item.id)
                            .onTapGesture {
                                switch item {
                                case .photo(let data): controller.selectedPhoto = data
                                case .video(let url): Task { await controller.playRecording(url: url) }
                                }
                            }
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(selected ? .yellow : .clear, lineWidth: 2)
                            )
                            .overlay(alignment: .topTrailing) {
                                DeleteButton { controller.delete(item) }
                            }
                    }
                }
                .padding(.horizontal, 8)
            }
            .frame(height: 62)
            .background(.black.opacity(0.8))
            .onChange(of: controller.roll.count) {
                if let last = controller.roll.last {
                    proxy.scrollTo(last.id, anchor: .trailing)
                }
            }
        }
    }

    var controls: some View {
        HStack(spacing: 30) {
            if controller.phase == .playing || controller.selectedPhoto != nil {
                Button(action: {
                    controller.selectedPhoto = nil
                    Task { await controller.live() }
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
                    Task { await controller.takeSnapshot() }
                }) {
                    ZStack {
                        Circle().stroke(.white, lineWidth: 4).frame(width: 64, height: 64)
                        Circle().fill(.white).frame(width: 52, height: 52)
                    }
                }
                .buttonStyle(.plain)
                .disabled(controller.phase != .live)

                Button(action: { Task { await controller.toggleRecording() } }) {
                    ZStack {
                        Circle().stroke(.red, lineWidth: 4).frame(width: 56, height: 56)
                        if controller.phase == .recording {
                            RoundedRectangle(cornerRadius: 4).fill(.red).frame(width: 24, height: 24)
                        } else {
                            Circle().fill(.red).frame(width: 44, height: 44)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(controller.isStopping || (controller.phase != .live && controller.phase != .recording))
            }
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(.black.opacity(0.8))
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

@TLAModel
struct CameraWorkflow {
    enum Phase: String, CaseIterable, FiniteTLAValueDomain {
        case starting, live, recording, playing

        static var defaultValue: Self { .starting }
        static let finiteValues = allCases
        var tlaValue: TLAValue { .string(rawValue) }
    }

    private enum ReadyProcess: String, FiniteTLAValueDomain { case readyEvent
        static var defaultValue: Self { .readyEvent }
        static let finiteValues: [Self] = [.readyEvent]
        var tlaValue: TLAValue { .string(rawValue) }
    }
    private enum RecordProcess: String, FiniteTLAValueDomain { case recordEvent
        static var defaultValue: Self { .recordEvent }
        static let finiteValues: [Self] = [.recordEvent]
        var tlaValue: TLAValue { .string(rawValue) }
    }
    private enum RecordingFinishedProcess: String, FiniteTLAValueDomain { case recordingFinishedEvent
        static var defaultValue: Self { .recordingFinishedEvent }
        static let finiteValues: [Self] = [.recordingFinishedEvent]
        var tlaValue: TLAValue { .string(rawValue) }
    }
    private enum PlayProcess: String, FiniteTLAValueDomain { case playEvent
        static var defaultValue: Self { .playEvent }
        static let finiteValues: [Self] = [.playEvent]
        var tlaValue: TLAValue { .string(rawValue) }
    }
    private enum LiveProcess: String, FiniteTLAValueDomain { case liveEvent
        static var defaultValue: Self { .liveEvent }
        static let finiteValues: [Self] = [.liveEvent]
        var tlaValue: TLAValue { .string(rawValue) }
    }
    private enum Step: String, CaseIterable { case ready, record, recordingFinished, play, live }

    static var spec: TLASpec {
        #spec("CameraWorkflow") {
            Algorithm("CameraWorkflow", scoped: { scope in
                let phase = scope.sharedVar("phase", initial: Phase.starting)
                Each(ReadyProcess.all) { _ in
                    Do(Step.ready) { When(phase == Phase.starting); Assign(phase, to: Phase.live); Goto(Step.ready) }
                }
                Each(RecordProcess.all) { _ in
                    Do(Step.record) { When(phase == Phase.live); Assign(phase, to: Phase.recording); Goto(Step.record) }
                }
                Each(RecordingFinishedProcess.all) { _ in
                    Do(Step.recordingFinished) { When(phase == Phase.recording); Assign(phase, to: Phase.live); Goto(Step.recordingFinished) }
                }
                Each(PlayProcess.all) { _ in
                    Do(Step.play) { When(phase == Phase.live); Assign(phase, to: Phase.playing); Goto(Step.play) }
                }
                Each(LiveProcess.all) { _ in
                    Do(Step.live) { When(phase == Phase.playing); Assign(phase, to: Phase.live); Goto(Step.live) }
                }
                Invariant("validPhase") { phase == Phase.starting || phase == Phase.live || phase == Phase.recording || phase == Phase.playing }
            })
        }
    }

}

@MainActor
@Observable
final class CameraController {
    private var machine: CameraWorkflow?
    private(set) var capture: Media.Capture?
    var roll: [RollItem] = []
    var flashActive = false
    var selectedPhoto: Data?
    var recordedURL: URL?
    var currentPlayer: AVPlayer?
    var isStopping = false
    private let photoDirectory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures/SwiftTLA/camera")
    private var movieOutput: AVCaptureMovieFileOutput?
    private let recordDelegate = RecordingDelegate()
    var diagnostic: String?

    var phase: CameraWorkflow.Phase { machine?.state.phase ?? .starting }

    init() {
        do {
            machine = try CameraWorkflow.makeMachine()
            capture = try Media.Capture()
            try FileManager.default.createDirectory(at: photoDirectory, withIntermediateDirectories: true)
            recordDelegate.owner = self
        } catch {
            diagnostic = String(describing: error)
        }
    }

    private func send(_ action: CameraWorkflow.Action) -> Bool {
        guard var machine else {
            diagnostic = "The generated camera machine did not initialize."
            return false
        }
        do {
            _ = try machine.send(action)
            self.machine = machine
            diagnostic = nil
            return true
        } catch {
            diagnostic = String(describing: error)
            return false
        }
    }

    func takeSnapshot() async {
        guard let capture else {
            diagnostic = "The generated camera machine did not initialize."
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

    func toggleRecording() async {
        if phase == .recording {
            guard isStopping == false else { return }
            guard let movieOutput else {
                diagnostic = "The camera output is not ready."
                return
            }
            isStopping = true
            movieOutput.stopRecording()
        } else if phase == .live {
            guard let movieOutput else {
                diagnostic = "The camera output is not ready."
                return
            }
            guard send(.record) else { return }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("recording-\(UUID().uuidString).mov")
            recordedURL = url
            movieOutput.startRecording(to: url, recordingDelegate: recordDelegate)
        }
    }

    func playRecording(url: URL? = nil) async {
        recordedURL = url ?? recordedURL
        guard phase == .live, let url = recordedURL else { return }
        guard send(.play) else { return }
        let player = AVPlayer(url: url)
        currentPlayer = player
        player.play()
        NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: player.currentItem, queue: .main) { [weak self] _ in
            Task { await self?.live() }
        }
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

    fileprivate func recordingDidFinish(url: URL, error: Error?) {
        isStopping = false
        guard send(.recordingFinished) else { return }
        if let error {
            diagnostic = "Recording failed: \(error)"
            return
        }
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
    func ready() async {
        guard let capture,
              let device = AVCaptureDevice.default(for: .video) else {
            diagnostic = "No video capture device is available."
            return
        }
        do {
            try await capture.configure(device: device)
            let output = AVCaptureMovieFileOutput()
            capture.session.addOutput(output)
            movieOutput = output
            try await capture.start()
            if send(.ready) == false {
                try await capture.stop()
            }
        } catch {
            diagnostic = "Camera setup failed: \(error)"
        }
    }

    func live() async {
        guard send(.live) else { return }
        currentPlayer?.pause()
        currentPlayer = nil
    }
}

private final class RecordingDelegate: NSObject, AVCaptureFileOutputRecordingDelegate {
    weak var owner: CameraController?

    func fileOutput(_: AVCaptureFileOutput, didFinishRecordingTo url: URL,
                    from _: [AVCaptureConnection], error: Error?) {
        guard let owner else { return }
        Task { @MainActor in owner.recordingDidFinish(url: url, error: error) }
    }
}
