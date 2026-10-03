"""Exercise substituted action identities with TLC during hosted tool setup only."""
import hashlib
import gzip
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import uuid

if os.environ.get("GITHUB_ACTIONS") != "true":
    raise SystemExit("This TLC regression runs only in GitHub Actions")

java, tlc_jar, bridge_jar = (str(Path(argument).resolve()) for argument in sys.argv[1:])

with tempfile.TemporaryDirectory() as temporary:
    root = Path(temporary)
    (root / "Base.tla").write_text(r"""---- MODULE Base ----
EXTENDS Integers
CONSTANT K
VARIABLE x
SetValue(n) == x' = n
Stay(n) == UNCHANGED x
Init == x = 0
Next == \E n \in 1..K: (SetValue(n) \/ Stay(n))
====
""", encoding="utf-8")
    (root / "Middle.tla").write_text(r"""---- MODULE Middle ----
CONSTANT L
VARIABLE z
INSTANCE Base WITH K <- L, x <- z
====
""", encoding="utf-8")

    def run(name, source, compact=False):
        (root / f"{name}.tla").write_text(source, encoding="utf-8")
        (root / f"{name}.cfg").write_text("INIT Init\nNEXT Next\n", encoding="utf-8")
        events = root / (f"{name}.jsonl" + (".gz" if compact else ""))
        compact_option = ["-Dswifttla.tlc.graph.compact-gzip=true"] if compact else []
        result = subprocess.run([
            java, f"-Dswifttla.tlc.graph.path={events}",
            f"-Dswifttla.tlc.graph.run-id={uuid.uuid4()}", f"-Dswifttla.tlc.graph.case-id={name}",
            *compact_option,
            "-cp", f"{tlc_jar}:{bridge_jar}", "tlc2.TLC",
            "-dump", "class,org.swifttla.conformance.LosslessStateWriter",
            "-workers", "1", "-config", f"{name}.cfg", f"{name}.tla",
        ], capture_output=True, text=True, timeout=30, cwd=root)
        assert result.returncode == 0, result.stdout + result.stderr
        data = gzip.open(events, "rb").read() if compact else events.read_bytes()
        lines = data.splitlines(keepends=True)
        records = [json.loads(line) for line in lines]
        assert all(record["version"] == (4 if compact else 3) for record in records)
        assert records[-1]["bodySha256"] == hashlib.sha256(b"".join(lines[:-1])).hexdigest()
        assert records[-1]["lastBodySeq"] == len(records) - 2
        return records

    wrapper = r"""---- MODULE Wrapper ----
VARIABLE y
INSTANCE Middle WITH L <- 2, z <- y
====
"""

    for records in [run("Wrapper", wrapper),
                    run("WrapperCompact", wrapper.replace("MODULE Wrapper", "MODULE WrapperCompact"), compact=True)]:
        assert not any(record["type"] == "unsupported" for record in records), records

        representatives = {}
        for record in records:
            if record["type"] == "initial":
                state = record["state"]
            elif record["type"] == "transition" and "bindings" in record["target"]:
                state = record["target"]
            else:
                continue
            representatives[state["fingerprint"]] = state

        def value(state):
            full = representatives[state["fingerprint"]]
            assert [binding["name"] for binding in full["bindings"]] == ["y"], full
            return int(full["bindings"][0]["tla"])

        assert {value(record["state"]) for record in records if record["type"] == "initial"} == {0}
        edges = set()
        multiple = False
        for record in records:
            if record["type"] != "transition":
                continue
            assert record["action"]["name"] == "Next", record
            multiple |= len(record["resolvedActions"]) > 1
            for action in record["resolvedActions"]:
                match = re.match(r"<(SetValue|Stay)\(([12])\) line ", action["location"])
                assert match and match[1] == action["name"] and action["named"], action
                edges.add((value(record["source"]), match[1], int(match[2]), value(record["target"])))
        expected = {(state, action, member, member if action == "SetValue" else state)
                    for state in range(3) for action in ("SetValue", "Stay") for member in (1, 2)}
        assert multiple and edges == expected, (edges, expected)

    records = run("Qualified", r"""---- MODULE Qualified ----
VARIABLE y
instance == INSTANCE Base WITH K <- 2, x <- y
Init == instance!Init
Next == instance!Next
====
""")
    assert any(record["type"] == "unsupported" and "qualified action identity" in record["reason"]
               for record in records), records
