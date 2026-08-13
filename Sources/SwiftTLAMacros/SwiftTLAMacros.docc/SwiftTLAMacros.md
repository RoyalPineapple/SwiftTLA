# ``SwiftTLAMacros``

Generate typed Swift machines from a `TLASpec` declaration.

## Overview

Apply ``TLAModel()`` to a model declaration. Nest ``TLAActor()`` or
``TLAObservable()`` inside that declaration when an actor or observable adapter
is required.

The macro parses the supported builder syntax, constructs the formal model,
and generates the public machine surface described in the `SwiftTLA` DocC
catalog.

## Topics

### Macros

- ``TLAModel()``
- ``TLAActor()``
- ``TLAObservable()``
