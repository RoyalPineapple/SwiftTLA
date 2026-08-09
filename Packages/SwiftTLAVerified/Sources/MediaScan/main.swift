import SwiftUI
@preconcurrency import SwiftTLAVerified
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
                                    model._live()
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
                        CameraPreviewView(session: model.capture.session)
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
            }
            .background(.black)
            .frame(minWidth: 640, minHeight: 520)
            .task { model._ready() }
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
                                case .video(let url): model.playRecording(url: url)
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
                    model._live()
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

                Button(action: { model.toggleRecording() }) {
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
    required init?(coder: NSCoder) { fatalError() }
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
    required init?(coder: NSCoder) { fatalError() }
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

@Observable
@TLAObservable
final class CameraModel {
    static var spec: TLASpec {
        TLASpec("CameraModel") {
            let phase = StateVar(0)

            Action("_ready")  { phase == 0 && phase.becomes(1) }
            Action("_record") { phase == 1 && phase.becomes(2) }
            Action("_stop")   { phase == 2 && phase.becomes(1) }
            Action("_play")   { phase == 1 && phase.becomes(3) }
            Action("_live")   { phase == 3 && phase.becomes(1) }

            Invariant("validPhase") { phase >= 0 && phase <= 3 }
        }
    }

    let capture = Media.Capture()
    var roll: [RollItem] = []
    var flashActive = false
    var selectedPhoto: Data?
    var recordedURL: URL?
    var currentPlayer: AVPlayer?
    private let disk = DiskStore(name: "camera")
    private var movieOutput: AVCaptureMovieFileOutput?
    private let recordDelegate = RecordingDelegate()

    init() {
        onReady = { [weak self] from, to in
            guard let self, let device = AVCaptureDevice.default(for: .video) else { return }
            do {
                try await self.capture.configure(device: device)
                let sess = await self.capture.session
                let mo = AVCaptureMovieFileOutput()
                sess.addOutput(mo)
                self.movieOutput = mo
                try await self.capture.start()
            } catch {
                print("Camera error: \(error)")
            }
        }
        onRecord = { [weak self] from, to in
            guard let self, let mo = self.movieOutput else { return }
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("recording-\(UUID().uuidString).mov")
            self.recordedURL = url
            mo.startRecording(to: url, recordingDelegate: self.recordDelegate)
        }
        onStop = { [weak self] from, to in
            self?.movieOutput?.stopRecording()
            if let url = self?.recordedURL { self?.roll.append(.video(url)) }
            self?.recordedURL = nil
        }
        onPlay = { [weak self] from, to in
            guard let self, let u = self.recordedURL else { return }
            let player = AVPlayer(url: u)
            self.currentPlayer = player
            player.play()
            NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime,
                                                   object: player.currentItem, queue: .main) { [weak self] _ in
                self?._live()
            }
        }
        onLive = { [weak self] from, to in
            self?.currentPlayer?.pause()
            self?.currentPlayer = nil
        }
    }

    func takeSnapshot() async {
        do {
            let data = try await capture.capturePhoto()
            roll.append(.photo(data))
            flashActive = true
            try? await disk.write(name: "snap-\(Int(Date().timeIntervalSince1970)).jpg", data: data)
            try? await Task.sleep(for: .milliseconds(120))
            flashActive = false
        } catch {
            print("Snapshot error: \(error)")
        }
    }

    func toggleRecording() {
        if phase == 2 { _stop() }
        else if phase == 1 { _record() }
    }

    func playRecording(url: URL? = nil) {
        recordedURL = url ?? recordedURL
        if phase == 1 { _play() }
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
}

private final class RecordingDelegate: NSObject, AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_: AVCaptureFileOutput, didFinishRecordingTo url: URL,
                    from _: [AVCaptureConnection], error: Error?) {
        if let error { print("Record error: \(error)") }
        else { print("Recorded: \(url.path)") }
    }
}
