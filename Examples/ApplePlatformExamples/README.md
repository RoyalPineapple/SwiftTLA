# Apple Platform Examples

This macOS package contains two separate SwiftTLA consumer applications:

- `bluetooth-example`: a CoreBluetooth central and per-peripheral actor example.
- `bluetooth-cli`: the same Bluetooth actor as a terminal scanner. Use
  `swift run bluetooth-cli --seconds 20`.
- `av-pipeline-example`: an AVFoundation capture, writer, and player pipeline.

`Bluetooth` and `AVPipeline` are separate library targets. Each app imports only
the model it demonstrates. Both consume the local SwiftTLA package through
`../../Package.swift`; every example source remains outside the SwiftTLA library target.

The Bluetooth model comments identify the central policy, the per-device lifecycle,
the bounded symmetric verification population, and the generated-machine ID routing.

## Camera adoption proof

`av-pipeline-example` is the external generated-machine proof. `CameraWorkflow`
owns the typed formal `State`, `Action`, and `Transition` values; the SwiftUI
app uses the generated machine for every state change. The focused adoption
tests exercise the generated actor under concurrent sends. The app never reads or exposes a raw
TLA state map, compiled storage, or compiler-internal API.

AVFoundation stays at the application edge. Each recording request has an
immutable attempt ID and one callback delegate. One correlation value classifies its
completion, failure, or cancellation before submitting exactly one matching
typed outcome action. A late or duplicate callback is logged and ignored, so it
cannot change a later request's generated state.

### Supported verification

Run the focused package contracts serially through the repository wrapper:

```sh
../../scripts/local-validation.sh xcode-test ApplePlatformExamplesTests/GeneratedAppleModelTests
../../scripts/local-validation.sh xcode-test ApplePlatformExamplesTests/CameraAdoptionProofTests
```

The hosted `apple-platform-examples` job runs
`xcodebuild -scheme av-pipeline-example -destination 'platform=macOS' -jobs 1 build`,
runs both focused suites in one serial test invocation, verifies that each suite
passed exactly six tests, and uploads the four records as one SHA-named artifact.
GitHub Actions is the admission authority. After push, release
reviewers verify that the hosted run and its artifact belong to the submitted
SHA before making an admission decision.

### Manual camera check (pending)

On a macOS host with an available camera and the required permission:

1. Build and launch `av-pipeline-example`, then confirm the displayed generated
   state reaches `live`.
2. Start and stop a recording; confirm the state returns to `live` after the
   resulting media is retained at the application edge.
3. Start a second recording and cancel it; confirm its typed cancellation
   outcome returns the generated state to `live`.
4. With a permitted removable camera, start a recording and disconnect the
   active camera before it finishes. Confirm the callback submits
   `.recordingFailed`, the displayed generated state returns to `live`, and
   retain the shown recording operation ID and error diagnostic. If no approved
   controlled-failure setup is available, record this sub-check as an unmet
   manual gate rather than treating cancellation or a synthetic action as a
   failure result.
5. Use **Demonstrate Rejection** from `live`; confirm the diagnostic names the
   rejected action and preserves the displayed prior/current generated state.

Hardware permission and real camera media are manual checks. This walkthrough
is pending until it is performed on permitted hardware, including the
controlled-failure sub-check; the focused tests cover the deterministic
completion, failure, cancellation, late-callback, and duplicate-callback
contracts without representing the manual result as done.
