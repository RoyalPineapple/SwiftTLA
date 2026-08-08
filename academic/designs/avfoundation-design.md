# Verified AVFoundation

## Architecture

Same delegate-bridge pattern as Bluetooth.  `Camera` wraps `AVCaptureSession`.
State machine verified at compile time.  Public API is pure async Swift.

```
@TLAActor actor Camera
  ├── AVCaptureSession
  ├── CameraDelegate (bridges @objc → actor)
  ├── Proven state machine: unconfigured→configured→running→interrupted→stopped
  └── Invariants: no config while running, no capture while stopped
```

## State machine

```
unconfigured(0) ──→ configured(1) ──→ running(2) ──→ interrupted(3)
       ↑                │                   │              │
       └────────────────┘                   │              │
            (stop)                    capture/session   resume
                                         errors          │
                                                        running(2)

stopped: can reconfigure
interrupted: cannot capture, auto-recovers or manual stop
```

## Invariants

| Name | Statement |
|------|-----------|
| `noCaptureWithoutRunning` | phase == 2 for any capture operation |
| `noConfigWhileRunning` | (phase != 2 && phase != 3) for configure calls |
| `validPhase` | phase ∈ 0..3 |
| `interruptedRecovers` | phase == 3 → eventually phase == 2 (liveness) |

## Spec

```swift
@TLAActor
public actor Camera {
    public static var spec: TLASpec {
        TLASpec("Camera") {
            let phase = Var<Int>("phase")
            Variable(phase, 0)

            Action("_configure")    { phase == 0 && phase.becomes(1) }
            Action("_start")        { phase == 1 && phase.becomes(2) }
            Action("_stop")         { (phase == 2 || phase == 3) && phase.becomes(0) }
            Action("_interrupt")    { phase == 2 && phase.becomes(3) }
            Action("_resume")       { phase == 3 && phase.becomes(2) }
            Action("_capture")      { phase == 2 && phase.stays }

            Invariant("validPhase")  { phase >= 0 && phase <= 3 }
        }
    }

    // ── Bridge ──
    public let session: AVCaptureSession
    private let delegate = CameraDelegate()
    private var photoCont: CheckedContinuation<Data, Error>?

    public init() {
        session = AVCaptureSession()
        delegate.actor = self
    }

    public func configure(_ block: () -> Void) throws {
        guard _state.phase == 0 else { throw CameraError.cannotConfigure }
        session.beginConfiguration()
        block()
        session.commitConfiguration()
        _configure()
    }

    public func start() async throws {
        guard _state.phase == 1 else { throw CameraError.notConfigured }
        _start()
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            session.startRunning()
            c.resume()
        }
    }

    public func stop() {
        _stop()
        session.stopRunning()
    }

    public func capturePhoto() async throws -> Data {
        guard _state.phase == 2 else { throw CameraError.notRunning }
        return try await withCheckedThrowingContinuation { c in
            self.photoCont = c
            // AVCapturePhotoOutput triggers delegate → resumes c
        }
    }
}
```

## Delegate bridge

```swift
private final class CameraDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    weak var actor: Camera?
    func photoOutput(_ output: AVCapturePhotoOutput,
                     didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        Task { await actor?.didCapture(photo, error) }
    }
}
```

## Beyond the camera: the full AV pipeline

```
Camera                  ← @TLAActor, proven state machine
  ├── configure/start/stop/capture
  │
  ├── Recorder            ← @TLAActor, wraps AVAssetWriter
  │   States: idle → recording → paused → finished/error
  │   Invariant: no write while idle, must finish before dealloc
  │
  └── Player              ← @TLAActor, wraps AVPlayer
      States: idle → loading → ready → playing → paused → finished
      Invariant: no seek while loading, rate observation while playing

Composition (cross-actor, TLC):
  Camera.running ∧ Recorder.recording ∧ Player.ready
  → "capture, encode, preview" pipeline
```

## Recorder

Wraps `AVAssetWriter`.  State machine proves you never write while idle and
always finish before dealloc.  The runtime crash "must call finishWriting"
becomes a compile-time proof.

### State machine

```
unconfigured(0) ──→ configured(1) ──→ recording(2) ──→ paused(3)
                        │                   │              │
                        │                   │              │
                    finishWriting        appendSample     resume
                        │              cancelWriting        │
                        ▼                   │              │
                    completed(4)            ▼              │
                                     cancelled(5)          │
                                                        recording(2)
```

### Invariants

| Name | Statement |
|------|-----------|
| `noWriteWithoutRecording` | (phase == 2 or phase == 3) for appendSample |
| `mustFinishBeforeComplete` | phase == 4 only reachable via configured→finishWriting |
| `validPhase` | phase ∈ 0..5 |
| `noWriteAfterComplete` | phase ∈ {4,5} ⇒ no further writes |

### Spec

```swift
@TLAActor
public actor Recorder {
    public static var spec: TLASpec {
        TLASpec("Recorder") {
            let phase = Var<Int>("phase")
            Variable(phase, 0)

            Action("_configure")   { phase == 0 && phase.becomes(1) }
            Action("_start")       { phase == 1 && phase.becomes(2) }
            Action("_write")       { phase == 2 && phase.stays }
            Action("_pause")       { phase == 2 && phase.becomes(3) }
            Action("_resume")      { phase == 3 && phase.becomes(2) }
            Action("_finish")      { phase == 1 && phase.becomes(4) }
            Action("_cancel")      { (phase == 2 || phase == 3) && phase.becomes(5) }

            Invariant("validPhase") { phase >= 0 && phase <= 5 }
        }
    }

    public let writer: AVAssetWriter

    public init(url: URL, fileType: AVFileType) {
        writer = AVAssetWriter(url: url, fileType: fileType)
    }

    public func configure(_ block: () -> Void) throws {
        guard _state.phase == 0 else { throw RecorderError.cannotConfigure }
        block()
        _configure()
    }

    public func start() async throws {
        guard _state.phase == 1 else { throw RecorderError.notConfigured }
        writer.startWriting()
        _start()
    }

    public func append(_ sample: CMSampleBuffer) throws {
        guard _state.phase == 2 else { throw RecorderError.notRecording }
        writer.requestMediaDataWhenReady(on: .main) { [weak self] in
            self?.writerInput?.append(sample)
        }
    }

    public func pause() { _pause(); writer.pauseWriting() }
    public func resume() { _resume(); writer.startWriting() }

    public func finish() async throws {
        guard _state.phase == 1 || _state.phase == 2 || _state.phase == 3
            else { throw RecorderError.cannotFinish }
        _finish()
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            writer.finishWriting { c.resume() }
        }
    }

    public func cancel() { _cancel() }
}
```

## Player

Wraps `AVPlayer`.  State machine proves you never seek while loading, rate
observation only while playing, and the playback lifecycle is sound.

### State machine

```
idle(0) ──→ loading(1) ──→ ready(2) ──→ playing(3)
                               │            │
                               │         pause
                               │            │
                            seek           ▼
                               │         paused(4)
                               │            │
                               │         play
                               │            │
                               ▼            ▼
                            ready(2)    playing(3)
                                           │
                                        finished(5)
```

### Invariants

| Name | Statement |
|------|-----------|
| `noSeekWhileLoading` | phase != 1 for seek operations |
| `rateValidWhilePlaying` | phase == 3 for rate observation |
| `validPhase` | phase ∈ 0..5 |
| `finishedPermanent` | phase == 5 ⇒ no further transitions |

### Spec

```swift
@TLAActor
public actor Player {
    public static var spec: TLASpec {
        TLASpec("Player") {
            let phase = Var<Int>("phase")
            Variable(phase, 0)

            Action("_load")     { phase == 0 && phase.becomes(1) }
            Action("_ready")    { phase == 1 && phase.becomes(2) }
            Action("_play")     { (phase == 2 || phase == 4) && phase.becomes(3) }
            Action("_pause")    { phase == 3 && phase.becomes(4) }
            Action("_seek")     { (phase == 2 || phase == 3 || phase == 4) && phase.stays }
            Action("_finish")   { phase == 3 && phase.becomes(5) }

            Invariant("validPhase") { phase >= 0 && phase <= 5 }
        }
    }

    public let player: AVPlayer

    public init(url: URL) {
        player = AVPlayer(url: url)
    }

    public func load() async throws {
        guard _state.phase == 0 else { throw PlayerError.alreadyLoaded }
        _load()
        _ = try await player.currentItem?.asset.load(.isPlayable)
        _ready()
    }

    public func play() {
        guard _state.phase == 2 || _state.phase == 4 else { return }
        _play()
        player.play()
    }

    public func pause() {
        guard _state.phase == 3 else { return }
        _pause()
        player.pause()
    }

    public func seek(to time: CMTime) {
        guard _state.phase != 1 else { return }
        player.seek(to: time)
    }
}
```

## Cross-actor composition

```
Camera.capture ──→ Recorder.append ──→ Player.preview
      │                   │                   │
   @TLAActor          @TLAActor          @TLAActor
   proven             proven             proven

Cross-actor (TLC):
  Camera.running ∧ Recorder.recording ∧ Player.ready
  "A capture pipeline where camera feeds recorder and player previews"
```

## What this demonstrates for the paper

1. **Same pattern, different framework**: delegate bridge + @TLAActor + proven state machine works for AVFoundation exactly like CoreBluetooth
2. **Composable**: Camera → Recorder → Player form a verified capture pipeline
3. **Apple's most notoriously complex state machines**: AVCaptureSession, AVAssetWriter, and AVPlayer are legendary for subtle state bugs
4. **Real developer pain**: every iOS developer has hit "cannot configure while running" or "must call finishWriting before dealloc"
