"""Exercise substituted action identities with TLC during hosted tool setup only."""
import hashlib
import gzip
import json
import os
from pathlib import Path
import re
import struct
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

    def run(name, source, compact=False, binary=False):
        (root / f"{name}.tla").write_text(source, encoding="utf-8")
        (root / f"{name}.cfg").write_text("INIT Init\nNEXT Next\n", encoding="utf-8")
        events = root / (f"{name}.bin.gz" if binary else f"{name}.jsonl" + (".gz" if compact else ""))
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
        data = gzip.open(events, "rb").read() if compact or binary else events.read_bytes()
        if binary:
            return data
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

    (root / "StateDomain.tla").write_text(r"""---- MODULE StateDomain ----
VARIABLE x
Init == x = 0
Move(n) == x' = n
Next == \E n \in (IF x = 0 THEN {0,1} ELSE {0,1,2}): Move(n)
====
""", encoding="utf-8")
    state_domain_wrapper = r"""---- MODULE StateDomainWrapper ----
VARIABLE x
INSTANCE StateDomain
====
"""
    for records in [run("StateDomainWrapper", state_domain_wrapper),
                    run("StateDomainWrapperCompact", state_domain_wrapper.replace(
                        "MODULE StateDomainWrapper", "MODULE StateDomainWrapperCompact"), compact=True)]:
        assert not any(record["type"] == "unsupported" for record in records), records
        transitions = [record for record in records if record["type"] == "transition"]
        assert len(transitions) == 8, transitions
        assert all(len(record["resolvedActions"]) == 1 for record in transitions), transitions
        assert any(action["location"].startswith("<Move(2) line ")
                   for record in transitions for action in record["resolvedActions"]), transitions

    (root / "StateArgument.tla").write_text(r"""---- MODULE StateArgument ----
EXTENDS Integers
VARIABLE x
Init == x = 0
Move(n) == x' = 1 - n
Next == Move(x)
====
""", encoding="utf-8")
    state_argument_wrapper = r"""---- MODULE StateArgumentWrapper ----
VARIABLE y
INSTANCE StateArgument WITH x <- y
====
"""
    for records in [run("StateArgumentWrapper", state_argument_wrapper),
                    run("StateArgumentWrapperCompact", state_argument_wrapper.replace(
                        "MODULE StateArgumentWrapper", "MODULE StateArgumentWrapperCompact"), compact=True)]:
        assert not any(record["type"] == "unsupported" for record in records), records
        states = {record["state"]["fingerprint"]: int(record["state"]["bindings"][0]["tla"])
                  for record in records if record["type"] == "initial"}
        states.update({record["target"]["fingerprint"]: int(record["target"]["bindings"][0]["tla"])
                       for record in records if record["type"] == "transition"
                       and "bindings" in record["target"]})
        edges = {(states[record["source"]["fingerprint"]], action["location"].split(" line ")[0],
                  states[record["target"]["fingerprint"]])
                 for record in records if record["type"] == "transition"
                 for action in record["resolvedActions"]}
        assert edges == {(0, "<Move(0)", 1), (1, "<Move(1)", 0)}, edges

    binary = run("StateArgumentWrapperBinary", state_argument_wrapper.replace(
        "MODULE StateArgumentWrapper", "MODULE StateArgumentWrapperBinary"), binary=True)
    assert binary.startswith(b"STLAGRF2"), binary[:8]
    action = struct.pack(">BII", 1, 0, 4) + b"Next"
    offset = binary.find(action)
    assert offset >= 0, "binary action must retain the selected outer Next identity"
    length = struct.unpack_from(">I", binary, offset + len(action))[0]
    location = binary[offset + len(action) + 4:offset + len(action) + 4 + length].decode()
    assert location.startswith("<Move(0)"), location

    records = run("Qualified", r"""---- MODULE Qualified ----
VARIABLE y
instance == INSTANCE Base WITH K <- 2, x <- y
Init == instance!Init
Next == instance!Next
====
""")
    assert any(record["type"] == "unsupported" and "qualified action identity" in record["reason"]
               for record in records), records
