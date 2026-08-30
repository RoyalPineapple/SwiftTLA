# SwiftTLA examples

The examples consume one generated SwiftTLA machine as their state-transition
authority.

Each example has three layers:

1. A SwiftTLA specification defines the state, allowed transitions, and
   formal properties.
2. A generated machine or generated `Actor` owns the executable state and
   applies those transitions.
3. A thin application adapter receives platform events, invokes generated
   actions, and renders generated state.

For example, a CoreBluetooth delegate maps discovery and connection callbacks
to generated actions, with connection phase owned by generated state. A
SwiftUI view stores a generated machine in `@State` and delegates transition
legality to that machine.

Keep platform values at the edge. A record in the model can hold a formal
device identifier or other formal state; the adapter maps that identifier to
the concrete `CBPeripheral`, AVFoundation object, or UI effect.

Tests belong beside the example models. They run the generated transition and
state checks through generated machine APIs. The app demonstrates those same
generated machines in use.

## Packages

- `SwiftTLADemos` contains the source models and their tests for the bespoke
  demonstrations.
- `SwiftTLADemoApp` is the SwiftUI application that imports `SwiftTLADemos`.
- `ApplePlatformExamples` contains separate Apple-framework consumers of the
  SwiftTLA library.

When an example needs a new behavior, add the smallest typed formal capability
required by the source model. The source model declares that behavior, and the
generated machine executes it.
