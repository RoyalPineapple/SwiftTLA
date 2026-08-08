# Camera — TLA+ → SwiftTLA Pipeline

## Methodology

1. Write genuine TLA+ specification
2. Validate with TLC (ground truth)
3. Port to SwiftTLA @TLAActor
4. Verify state count matches TLC exactly

## TLA+ Spec (ground truth)

```
---- MODULE Camera ----
EXTENDS Integers
VARIABLE phase

Init == phase = 0    \* 0=unconfigured

Configure == phase = 0 /\ phase' = 1
Start     == phase = 1 /\ phase' = 2
Stop      == (phase = 2 \/ phase = 3) /\ phase' = 0
Interrupt == phase = 2 /\ phase' = 3
Resume    == phase = 3 /\ phase' = 2

Next == Configure \/ Start \/ Stop \/ Interrupt \/ Resume
Spec == Init /\ [][Next]_phase
ValidPhase == phase >= 0 /\ phase <= 3
====
```

## TLC Results

```
7 states generated, 4 distinct states found, 0 states left on queue.
The depth of the complete state graph search is 4.
```

Invariant `ValidPhase` holds. No deadlocks.

## SwiftTLA Port

```swift
@TLAActor
public actor Camera {
    public static var spec: TLASpec {
        TLASpec("Camera") {
            let phase = Var<Int>("phase")
            Variable(phase, 0)
            Action("_configure")  { phase == 0 && phase.becomes(1) }
            Action("_start")      { phase == 1 && phase.becomes(2) }
            Action("_stop")       { (phase == 2 || phase == 3) && phase.becomes(0) }
            Action("_interrupt")  { phase == 2 && phase.becomes(3) }
            Action("_resume")     { phase == 3 && phase.becomes(2) }
            Invariant("validPhase") { phase >= 0 && phase <= 3 }
        }
    }
}
```

## Matching Criteria

- TLC: 4 distinct states. SwiftTLA: 4 distinct states. ✅ Match.
- Invariant `validPhase` verified by both TLC and @TLAActor macro. ✅ Match.
- Compile-time verification: @TLAActor fails build if invariant violated. ✅ Match.
