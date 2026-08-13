# ``SwiftTLA``

Define a finite behavioral model once. Then inspect, execute, and verify the
same model from Swift.

## Overview

`SwiftTLA` contains the formal value model, parser support, checker, runtime,
and guarded application boundary. The `SwiftTLAMacros` module contains the
macros that generate typed machines from a `TLASpec` declaration.

Application code reads generated `State`, `ActionLabel`, and
`TransitionResult` values. It does not read a raw formal state map.

## Topics

### State boundaries

- ``TLAStateProjection``
- ``TLAStateProjectionResult``
- ``TLAStateProjectionDiagnostic``
- ``TLAMachineObservation``
- ``TLAMachineAvailabilityDiagnostic``

### Machine protocols

- ``TLAMachineObserving``
- ``TLAMachineExecuting``
- ``TLAMachineAdapterCanonicalModel``
- ``TLAMachineAdapterAccess``

### Runtime action identity

- ``TLAActionInvocation``
- ``GeneratedMachineError``

### Generated-machine reference

- <doc:GeneratedMachineSurface>
