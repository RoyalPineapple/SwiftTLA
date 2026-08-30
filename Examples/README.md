# SwiftTLA examples

The examples are consumers of SwiftTLA. They do not contain a second state
machine, scheduler, or rules engine.

Each example has three layers:

1. A SwiftTLA specification defines the state, allowed transitions, and
   formal properties.
2. A generated machine or generated `Actor` owns the executable state and
   applies those transitions.
3. A thin application adapter receives platform events, invokes generated
   actions, and renders generated state.

For example, a CoreBluetooth delegate maps discovery and connection callbacks
to generated actions. It does not keep a parallel connection-phase variable.
A SwiftUI view stores a generated machine in `@State`. It does not decide
which formal transition is legal.

Keep platform values at the edge. A record in the model can hold a formal
device identifier or other formal state; the adapter maps that identifier to
the concrete `CBPeripheral`, AVFoundation object, or UI effect.

Tests belong beside the example models. They run the generated transition and
state checks. The app exists to demonstrate the same generated machines in use,
not to reimplement their verification.

## Packages

- `SwiftTLADemos` contains the source models and their tests for the bespoke
  demonstrations.
- `SwiftTLADemoApp` is the SwiftUI application that imports `SwiftTLADemos`.
- `ApplePlatformExamples` contains separate Apple-framework consumers of the
  SwiftTLA library.

When an example needs behavior the current DSL cannot state, add the smallest
typed formal capability required by the source model. Do not patch the app
with imperative fallback logic.
