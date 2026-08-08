# Layered Spec Generation — Design

## Goal

Each `@TLAActor` TLASpec generates two things:
1. Internal state machine (apply methods, State struct) — already implemented
2. Public interface — a protocol listing the transitions as callable methods

Parent specs import child interfaces and generate coordinator methods that call
into children with cross-actor guards.

## Layer 1: Bottom (Capture)

```swift
@TLAActor
actor Capture {
    static var spec: TLASpec { ... }
}

// ── Generated ──
protocol CaptureProtocol {
    func configure()
    func start()
    func stop()
    func interrupt()
    func resume()
}

extension Capture: CaptureProtocol {
    // generated: state machine guards + apply methods
    func configure() { guard _state.phase == 0; _state = _apply(.configure) }
    func start()     { guard _state.phase == 1; _state = _apply(.start) }
    ...
}
```

## Layer 2: Middle (Camera System)

Imports Capture + Writer interfaces. Adds cross-actor guards.

```swift
@TLAActor
actor CameraSystem {
    let capture: CaptureProtocol   // ← imported interface
    let writer: WriterProtocol     // ← imported interface

    static var spec: TLASpec {
        TLASpec("CameraSystem") {
            #importSpec("Capture")    // expands to Capture's variables + actions
            #importSpec("Writer")     // expands to Writer's variables + actions

            // Cross-actor overrides
            Action("writerStart") { wPhase == 1 && cPhase == 2 && wPhase.becomes(2) }
            Action("captureStop") { (cPhase == 2 || cPhase == 3) && (wPhase != 2 && wPhase != 3) && cPhase.becomes(0) }
        }
    }
}

// ── Generated ──
protocol CameraSystemProtocol {
    func startRecording()  // calls capture.start() + writer.start() with cross-actor guards
    func stopRecording()   // calls writer.finish() + capture.stop() with cross-actor guards
}

extension CameraSystem: CameraSystemProtocol {
    func startRecording() {
        // Generated from cross-actor guards:
        guard cPhase == 2  // proven: capture must be running
        capture.start()     // calls child's generated method
        writerStart()       // own state transition
        writer.start()      // calls child's generated method
    }
}
```

## Layer 3: Top (Media Pipeline)

Imports CameraSystem + Player interfaces.

```swift
@TLAActor
actor MediaPipeline {
    let camera: CameraSystemProtocol
    let player: PlayerProtocol

    static var spec: TLASpec {
        TLASpec("MediaPipeline") {
            #importSpec("CameraSystem")
            #importSpec("Player")

            Action("playerPlay") { pPhase == 2 && wPhase == 4 && pPhase.becomes(3) }

            Invariant("playerRequiresWriter") { (pPhase != 3) || (wPhase == 4) }
        }
    }
}

// ── Generated ──
protocol MediaPipelineProtocol {
    func recordAndPlay()
}

extension MediaPipeline: MediaPipelineProtocol {
    func recordAndPlay() {
        camera.startRecording()  // calls middle layer
        camera.stopRecording()
        playerPlay()
        player.play()
    }
}
```

## The `#importSpec` macro (for @TLAActor parser)

When the parser encounters `#importSpec("Capture")`, it:
1. Scans the file for `@TLAActor actor Capture { ... }`
2. Parses the spec's variables and actions
3. Adds them to the parent spec's parsed components
4. The parent @TLAActor generates coordinator methods that call child methods

This works because all specs are in ONE FILE. The @TLAActor macro receives the
entire file's syntax tree. It can find child declarations and resolve them.

## What changes from current @TLAActor

1. When generating methods, also generate a protocol
2. When encountering `#importSpec(name)`, scan file for child specs
3. Generate coordinator methods that compose child calls + cross-actor guards
4. All layers in one file to enable compile-time resolution
