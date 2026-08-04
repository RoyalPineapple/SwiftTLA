# HourClock

From Leslie Lamport's [Specifying Systems](https://lamport.azurewebsites.net/tla/book.html), Chapter 2.

A clock that ticks from 1 to 12 and wraps. 12 reachable states.

Original TLA+:
```tla
VARIABLES hr
Init == hr \in 1..12
Next == hr' = IF hr # 12 THEN hr + 1 ELSE 1
```
