"""Count successful intercepted allocator calls and requested bytes during a separate batch."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess

CASES = [(c,1) for c in ["clock","pulse.make","pulse.send","pulse.blocked","pulse.failure","fifo.cycle",
                         "nano.initial","nano.successors","nano.invariants","nano.project"]]
for n in [1,1024,16384]:
    CASES += [(c,n) for c in ["inventory.increment","inventory.touch","inventory.discard","inventory.keep32",
                              "hand.sameStorage","hand.checkedTouch","helper.touch","hand.inPlace","inventory.project","inventory.hash"]]
for n in [2,1024]:
    CASES += [(c,n) for c in ["choices.selected","choices.send","choices.enabled","choices.successors"]]
def main():
    p=argparse.ArgumentParser(description=__doc__)
    for arg in ["binary","dylib","output"]: p.add_argument(arg,type=Path)
    a=p.parse_args()
    rows=[]
    for case,n in CASES:
        count = 8 if case == "inventory.project" and n > 1000 else 96
        runs=[]
        for _ in range(2):
            cmd=[a.binary.resolve(),case,str(n),str(count),"1"]
            proc=subprocess.run(cmd,env=dict(os.environ,BENCH_ALLOCATIONS="1",DYLD_INSERT_LIBRARIES=str(a.dylib.resolve())),
                                capture_output=True,text=True,timeout=60)
            if proc.returncode: raise RuntimeError(f"{case} {n} exit {proc.returncode} {proc.stderr[:1000]}")
            h=json.loads(proc.stdout)["heap"]
            runs.append(h)
        assert all(h["calls"]==count for h in runs)
        if case == "clock": assert all(h["events"] == 0 for h in runs)
        rows.append({"case":case,"size":n,"runs":runs})
    with a.output.open("x") as f:
        json.dump({"binarySHA256":hashlib.sha256(a.binary.read_bytes()).hexdigest(),
                   "dylibSHA256":hashlib.sha256(a.dylib.read_bytes()).hexdigest(),"rows":rows},f,indent=2)
if __name__=="__main__": main()
