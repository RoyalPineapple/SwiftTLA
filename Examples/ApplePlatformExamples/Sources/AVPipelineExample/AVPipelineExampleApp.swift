import SwiftUI
@preconcurrency import AVPipeline
import SwiftTLA
import SwiftTLAMacros
import AVFoundation
import Observation

@main
struct CameraApp: App {
    @State private var model = CameraModel()

    var body: some Scene {
        WindowGroup {
            VStack(spacing: 0) {
                ZStack {
                    if model.phase == 3, let player = model.currentPlayer {
                        VideoPlayerView(player: player)
                            .overlay(alignment: .topTrailing) {
                                Button {
                                    model.currentPlayer?.pause()
                                    model.currentPlayer = nil
                                    Task { await model.live() }
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
                        if let capture = model.capture {
                            CameraPreviewView(session: capture.session)
                        } else {
                            Color.black
                        }
                    }

                    if let preview = model.selectedPhoto {
                        PhotoDetailView(data: preview) { model.selectedPhoto = nil }
                    } else if model.phase == 1, model.flashActive {
                        Rectangle().fill(.white).transition(.opacity)
                    }
                }
                .aspectRatio(4/3, contentMode: .fit)

                filmstrip
                controls
                if let diagnostic = model.diagnostic {
                    Text(diagnostic)
                        .foregroundStyle(.red)
                        .padding(8)
                }
            }
            .background(.black)
            .frame(minWidth: 640, minHeight: 520)
            .task { await model.ready() }
        }
    }

    var filmstrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(model.roll) { item in
                        let selected = model.isSelected(item)
                        ThumbnailView(item: item, size: CGSize(width: 72, height: 54))
                            .id(item.id)
                            .onTapGesture {
                                switch item {
                                case .photo(let data): model.selectedPhoto = data
                                case .video(let url): Task { await model.playRecording(url: url) }
                                }
                            }
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(selected ? .yellow : .clear, lineWidth: 2)
                            )
                            .overlay(alignment: .topTrailing) {
                                DeleteButton { model.delete(item) }
                            }
                    }
                }
                .padding(.horizontal, 8)
            }
            .frame(height: 62)
            .background(.black.opacity(0.8))
            .onChange(of: model.roll.count) {
                if let last = model.roll.last {
                    proxy.scrollTo(last.id, anchor: .trailing)
                }
            }
        }
    }

    var controls: some View {
        HStack(spacing: 30) {
            if model.phase == 3 || model.selectedPhoto != nil {
                Button(action: {
                    model.selectedPhoto = nil
                    Task { await model.live() }
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
                    Task { await model.takeSnapshot() }
                }) {
                    ZStack {
                        Circle().stroke(.white, lineWidth: 4).frame(width: 64, height: 64)
                        Circle().fill(.white).frame(width: 52, height: 52)
                    }
                }
                .buttonStyle(.plain)
                .disabled(model.phase != 1)

                Button(action: { Task { await model.toggleRecording() } }) {
                    ZStack {
                        Circle().stroke(.red, lineWidth: 4).frame(width: 56, height: 56)
                        if model.phase == 2 {
                            RoundedRectangle(cornerRadius: 4).fill(.red).frame(width: 24, height: 24)
                        } else {
                            Circle().fill(.red).frame(width: 44, height: 44)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(model.phase != 1 && model.phase != 2)
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
        if let cg = try? gen.copyCGImage(at: .zero, actualTime: nil) {
            return NSImage(cgImage: cg, size: size)
        }
        return nil
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
    private enum StopProcess: String, FiniteTLAValueDomain { case stopEvent
        static var defaultValue: Self { .stopEvent }
        static let finiteValues: [Self] = [.stopEvent]
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
    private enum Step: String, CaseIterable { case ready, record, stop, play, live }

    static var spec: TLASpec {
        #spec("CameraWorkflow") {
            Algorithm("CameraWorkflow", scoped: { scope in
                let phase = scope.sharedVar("phase", initial: 0)
                Each(ReadyProcess.all) { _ in
                    Do(Step.ready) { When(phase == 0); Assign(phase, to: 1); Goto(Step.ready) }
                }
                Each(RecordProcess.all) { _ in
                    Do(Step.record) { When(phase == 1); Assign(phase, to: 2); Goto(Step.record) }
                }
                Each(StopProcess.all) { _ in
                    Do(Step.stop) { When(phase == 2); Assign(phase, to: 1); Goto(Step.stop) }
                }
                Each(PlayProcess.all) { _ in
                    Do(Step.play) { When(phase == 1); Assign(phase, to: 3); Goto(Step.play) }
                }
                Each(LiveProcess.all) { _ in
                    Do(Step.live) { When(phase == 3); Assign(phase, to: 1); Goto(Step.live) }
                }
                Invariant("validPhase") { phase >= 0 && phase <= 3 }
            })
        }
    }

}

@MainActor
@Observable
final class CameraModel {
    private var machine: CameraWorkflow?
    private(set) var capture: Media.Capture?
    var roll: [RollItem] = []
    var flashActive = false
    var selectedPhoto: Data?
    var recordedURL: URL?
    var currentPlayer: AVPlayer?
    private var disk: DiskStore?
    private var movieOutput: AVCaptureMovieFileOutput?
    private let recordDelegate = RecordingDelegate()
    var diagnostic: String?

    var phase: Int { machine?.state.phase ?? 0 }

    init() {
        do {
            machine = try CameraWorkflow.makeMachine()
            capture = try Media.Capture()
            disk = try DiskStore(name: "camera")
        } catch {
            diagnostic = String(describing: error)
        }
    }

    private func send(_ action: CameraWorkflow.Action) -> Bool {
        guard var machine else {
            diagnostic = "The camera model did not initialize."
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
        guard let capture, let disk else {
            diagnostic = "The camera model did not initialize."
            return
        }
        do {
            let data = try await capture.capturePhoto()
            roll.append(.photo(data))
            flashActive = true
            try await disk.write(name: "snap-\(Int(Date().timeIntervalSince1970)).jpg", data: data)
            try await Task.sleep(for: .milliseconds(120))
            flashActive = false
        } catch {
            diagnostic = "Snapshot failed: \(error)"
        }
    }

    func toggleRecording() async {
        if phase == 2 {
            guard send(.stop) else { return }
            movieOutput?.stopRecording()
            if let url = recordedURL { roll.append(.video(url)) }
        } else if phase == 1 {
            guard send(.record) else { return }
            guard let movieOutput else { return }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("recording-\(UUID().uuidString).mov")
            recordedURL = url
            movieOutput.startRecording(to: url, recordingDelegate: recordDelegate)
        }
    }

    func playRecording(url: URL? = nil) async {
        recordedURL = url ?? recordedURL
        guard phase == 1, let url = recordedURL else { return }
        guard send(.play) else { return }
        let player = AVPlayer(url: url)
        currentPlayer = player
        player.play()
        NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: player.currentItem, queue: .main) { [weak self] _ in
            Task { await self?.live() }
        }
    }

    func delete(_ item: RollItem) {
        roll.removeAll { $0.id == item.id }
        if case .video(let url) = item { try? FileManager.default.removeItem(at: url) }
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
        guard send(.ready),
              let capture,
              let device = AVCaptureDevice.default(for: .video) else { return }
        do {
            try await capture.configure(device: device)
            let output = AVCaptureMovieFileOutput()
            capture.session.addOutput(output)
            movieOutput = output
            try await capture.start()
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
    func fileOutput(_: AVCaptureFileOutput, didFinishRecordingTo url: URL,
                    from _: [AVCaptureConnection], error: Error?) {
        if let error { print("Record error: \(error)") }
        else { print("Recorded: \(url.path)") }
    }
}
