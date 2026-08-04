# Coffee Can

From the TLA+ [Examples](https://github.com/tlaplus/Examples) repository.  
Remove beans from a can. Two black → add black. Two white → add black (remove 2 white). One of each → remove white. Parity of white beans is preserved.

```tla
VARIABLES black, white
Init == black = MaxBeans /\ white = MaxBeans
```
