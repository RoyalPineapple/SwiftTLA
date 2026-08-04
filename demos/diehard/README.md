# Die Hard

From the TLA+ [Examples](https://github.com/tlaplus/Examples) repository. Classic water jug puzzle: measure exactly 4 gallons using 3 and 5 gallon jugs. 16 reachable states.

```tla
VARIABLES big, small
Init == big = 0 /\ small = 0
FillSmall == small' = 3
FillBig == big' = 5
...
```
The solution is found by the model checker as an invariant violation: `big /= 4`.
