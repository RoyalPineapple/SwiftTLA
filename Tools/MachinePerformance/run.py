"""Run the release client serially with a repeatable shuffled order."""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import random
import re
import statistics
import subprocess
import time

scalar = ["clock", "hand.increment", "pulse.make", "pulse.send", "pulse.actor", "pulse.actorBurst",
          "pulse.blocked", "pulse.failure", "pulse.enabled", "fifo.cycle","nano.initial","nano.successors","nano.invariants","nano.project"]
cases = [(name, 1) for name in scalar]
for n in [1, 64, 1024, 16384]:
    cases += [(name, n) for name in ["inventory.make","inventory.increment","inventory.touch","inventory.keep32","inventory.discard",
                                     "inventory.project","inventory.invariant","inventory.hash","hand.touch","hand.sameStorage","hand.checkedTouch","helper.touch","hand.inPlace"]]
for n in [1,64,1024]:
    cases += [("inventory.append",n), ("hand.append",n)]
for n in [2,16,128,1024]:
    cases += [(name,n) for name in ["choices.initials","choices.selected","choices.ambiguousInit",
                                    "choices.send","choices.enabled","choices.successors"]]
for n in [5,16]:
    cases += [("coffee.send",n),("coffee.graph",n)]
for n in [4,64]:
    cases += [(name,n) for name in ["counter.cycle","counter.graph","counter.render"]]

def verify(row):
    name, n = row["name"], row["size"]
    calls = 1 + row["iterations"] * len(row["batchNS"]) + len(row["singleNS"])
    constant = {"pulse.make":0, "pulse.blocked":1, "pulse.failure":1,"pulse.enabled":1,
                "inventory.invariant":0,"inventory.project":3,"inventory.make":n,
                "inventory.append":n+1,"hand.append":n+1,"choices.initials":n,"choices.selected":n,
                "choices.ambiguousInit":n,"choices.send":1,"choices.enabled":1,"choices.successors":n,
                "nano.invariants":0,"nano.initial":2,"nano.successors":2,"nano.project":4,"coffee.send":n-1,"coffee.graph":n*(n+3)//2, "counter.cycle":n,"counter.graph":n+1}
    if name in constant:
        assert row["checksum"] == calls * constant[name], row
    if name in {"hand.increment","pulse.send","pulse.actor", "pulse.actorBurst","inventory.increment","inventory.touch","hand.touch","hand.sameStorage","hand.checkedTouch","helper.touch"}:
        assert row["checksum"] == sum(i ^ (i+1) for i in range(calls)), (name,n)
    if name == "inventory.keep32":
        assert row["checksum"] == sum(max(0,i-32) ^ (i+1) for i in range(calls)), (name,n)
    if name in {"hand.inPlace","inventory.discard","clock"}:
        assert row["checksum"] == calls * (calls+1)//2
    if name == "fifo.cycle":
        assert abs(row["checksum"] * 2 - calls) <= 1
    if name == "counter.render":
        assert row["checksum"] > calls * 100
    assert min(row["batchNS"]) > 0

def execute(binary, case, iterations, batches):
    start = time.monotonic_ns()
    p = subprocess.run(["/usr/bin/time","-lp",binary,case[0],str(case[1]),str(iterations),str(batches)],
                       capture_output=True, text=True, timeout=90)
    if p.returncode:
        raise RuntimeError(f"{case}: {p.stderr[:2000]}")
    row = json.loads(p.stdout)
    row["processWallNS"] = time.monotonic_ns()-start
    row["maxRSSBytes"] = int(re.search(r"(\d+)\s+maximum resident set size",p.stderr)[1])
    verify(row)
    return row

def quantile(values, p):
    return sorted(values)[math.ceil(len(values)*p)-1]

def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument("binary",type=Path)
    ap.add_argument("output",type=Path)
    args=ap.parse_args()
    binary=args.binary.resolve()
    out=args.output
    out.mkdir(parents=True,exist_ok=True)
    path=out/"samples.jsonl"
    if path.exists():
        ap.error("use a fresh measurement directory")
    params={"binarySHA256":hashlib.sha256(binary.read_bytes()).hexdigest(),"rounds":3,"batches":5,
            "maxIterations":50000, "targetBatchNS":8000000, "seed":397,"cases":cases,
            "host":os.uname().machine}
    bins={}
    for case in cases:
        row=execute(binary,case,4,2)
        per_op=statistics.median(row["batchNS"])/4
        bins[case]=max(1,min(params["maxIterations"],round(params["targetBatchNS"]/per_op)))
    (out/"protocol.json").write_text(json.dumps(params,indent=2))
    rng=random.Random(params["seed"])
    grouped={case:[] for case in cases}
    with path.open("x") as f:
        for r in range(params["rounds"]):
            order=cases.copy()
            rng.shuffle(order)
            for case in order:
                row=execute(binary,case,bins[case],params["batches"])
                row["round"]=r+1
                f.write(json.dumps(row)+"\n"); f.flush()
                grouped[case].append(row)
    summaries=[]
    for (name,size),rows in grouped.items():
        periods=[statistics.median(row["batchNS"])/row["iterations"] for row in rows]
        individual=[v for row in rows for v in row["singleNS"]]
        summaries.append({"case":name,"size":size,"nsPerOp":statistics.median(periods),
                          "minRoundNS":min(periods),"maxRoundNS":max(periods),
                          "singleP50NS":quantile(individual,.50),"singleP95NS":quantile(individual,.95),
                          "singleSamples":len(individual),"maxRSSBytes":max(r["maxRSSBytes"] for r in rows)})
    (out/"summary.json").write_text(json.dumps(summaries,indent=2))
    cold=[execute(binary,("pulse.make",1),1,1) for _ in range(15)]
    (out/"fresh-process.json").write_text(json.dumps(cold))
    print(f"{len(summaries)} cases, {sum(map(len,grouped.values()))} measured processes, 15 fresh launches")
if __name__=="__main__": main()
