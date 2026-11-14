#!/usr/bin/env python3
"""Retain compiler output with its binary; this does not interpret Swift."""

import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile


MODEL = "Sources/UpstreamParity/ValidationModels/CheckedAdditionPrefixInitialModel.swift"
WORKFLOW = ".github/workflows/validation-pipeline.yml"
SCRIPT = "scripts/retain-native-initial-source.py"
SOURCE = "native-initial-source.swift"
RECEIPT = "native-initial-source.json"
SCHEMA = "swifttla.compiler-native-initial-source-v1"
EXPANSION = "@__swiftmacro_14UpstreamParity*CheckedAdditionPrefixInitialModel*TLAModelfMm_.swift"


def require(condition, message):
    if not condition:
        raise ValueError(message)


def digest(path):
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(65536), b""):
            value.update(block)
    return value.hexdigest()


def inputs(root):
    paths = subprocess.check_output(["git", "ls-files", "-z"], cwd=root).decode().split("\0")[:-1]
    fixed = {"Package.swift", "Package.resolved", WORKFLOW, SCRIPT}
    selected = sorted(path for path in paths if path in fixed
                      or (path.startswith("Sources/") and path.endswith(".swift")))
    require(fixed.issubset(selected), "native-source cache inputs are missing")
    return {path: digest(root / path) for path in selected}


def source_range(data, root):
    require(b"\0" not in data, "NUL in compiler expansion")
    lines = data.decode("utf-8").splitlines()
    ranges = [line for line in lines if line.startswith("// original-source-range: ")]
    prefix = "// original-source-range: " + str(root / MODEL) + ":"
    require(len(ranges) == 1 and ranges[0].startswith(prefix),
            "compiler expansion has another source origin")
    require(re.fullmatch(r"[0-9]+:[0-9]+-[0-9]+:[0-9]+", ranges[0][len(prefix):]),
            "compiler expansion source range is malformed")
    return ranges[0]


def capture(root, binary, expansion, output, started, origin):
    require(type(started) is int and started > 0, "invalid native-source build start")
    require(not expansion.is_symlink() and expansion.is_file(), "missing compiler expansion")
    snapshot = expansion.stat()
    require(snapshot.st_mtime_ns >= started, "compiler expansion predates this build")
    require(not (output / SOURCE).exists() and not (output / RECEIPT).exists(),
            "native-source capture already exists")
    data = expansion.read_bytes()
    after = expansion.stat()
    require((after.st_ino, after.st_size, after.st_mtime_ns)
            == (snapshot.st_ino, snapshot.st_size, snapshot.st_mtime_ns),
            "compiler expansion changed during capture")
    original_range = source_range(data, root)
    receipt = {
        "schema": SCHEMA,
        "producerSHA": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=root).decode().strip(),
        "origin": origin,
        "producerSourceRoot": str(root),
        "buildStartedEpochNS": started,
        "expansionModifiedEpochNS": snapshot.st_mtime_ns,
        "compilerExpansionName": expansion.name,
        "originalSourceRange": original_range,
        "sourceSHA256": hashlib.sha256(data).hexdigest(),
        "binarySHA256": digest(binary),
        "inputs": inputs(root),
        "semanticInterpretation": "OPEN",
    }
    output.mkdir(parents=True, exist_ok=True)
    (output / SOURCE).write_bytes(data)
    (output / RECEIPT).write_text(json.dumps(receipt, indent=2) + "\n")


def verify(root, binary, output):
    receipt = json.loads((output / RECEIPT).read_text())
    require(receipt["schema"] == SCHEMA, "unsupported native-source receipt")
    require(re.fullmatch(r"[0-9a-f]{40}", receipt["producerSHA"]), "invalid source producer")
    origin = receipt["origin"]
    require(re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", origin["repository"]),
            "invalid source producer repository")
    require(all(re.fullmatch(r"[1-9][0-9]*", origin[key]) for key in ["runID", "attempt"])
            and re.fullmatch(r"[A-Za-z_][A-Za-z0-9_-]*", origin["job"]),
            "invalid source producer run or job")
    require(receipt["inputs"] == inputs(root), "native-source producer inputs differ")
    require(receipt["sourceSHA256"] == digest(output / SOURCE), "native source digest differs")
    require(receipt["binarySHA256"] == digest(binary), "native binary digest differs")
    name = receipt["compilerExpansionName"]
    require(Path(name).name == name and Path(name).match(EXPANSION),
            "another macro expansion was retained")
    require(Path(receipt["producerSourceRoot"]).is_absolute(), "invalid producer source root")
    require(receipt["semanticInterpretation"] == "OPEN", "capture receipt cannot assert semantics")
    require(type(receipt["buildStartedEpochNS"]) is int
            and type(receipt["expansionModifiedEpochNS"]) is int
            and receipt["expansionModifiedEpochNS"] >= receipt["buildStartedEpochNS"] > 0,
            "invalid native-source build interval")
    original_range = source_range((output / SOURCE).read_bytes(), Path(receipt["producerSourceRoot"]))
    require(original_range == receipt["originalSourceRange"], "native-source origin differs")
    return receipt


def self_check(root):
    # Protocol data only: no compiler execution or semantic proof is simulated.
    with tempfile.TemporaryDirectory() as directory:
        area = Path(directory)
        binary = area / "binary"
        binary.write_bytes(b"binary receipt test")
        expansion = area / "@__swiftmacro_14UpstreamParity33CheckedAdditionPrefixInitialModel8TLAModelfMm_.swift"
        expansion.write_text("// original-source-range: " + str(root / MODEL) + ":21:1-21:1\n")
        output = area / "retained"
        origin = {"repository": "RoyalPineapple/SwiftTLA", "runID": "1", "attempt": "1", "job": "prepare"}
        capture(root, binary, expansion, output, 1, origin)
        verify(root, binary, output)
        (output / SOURCE).write_bytes(b"changed compiler output")
        try:
            verify(root, binary, output)
        except ValueError:
            pass
        else:
            raise AssertionError("changed compiler output was accepted")
        try:
            capture(root, binary, expansion, area / "stale", expansion.stat().st_mtime_ns + 1, origin)
        except ValueError:
            pass
        else:
            raise AssertionError("a stale expansion was accepted")
    print("Native-source receipt integrity controls passed (no semantic proof credit).")


def main():
    root = Path(__file__).resolve().parents[1]
    if sys.argv[1:] == ["--self-check"]:
        self_check(root)
        return
    require(sys.argv[1:] == ["verify"] or len(sys.argv) == 3 and sys.argv[1] == "capture",
            "usage: retain-native-initial-source.py capture <build-start-epoch-ns> | verify | --self-check")
    tracked = subprocess.check_output(
        ["git", "status", "--porcelain", "--untracked-files=all", "--",
         "Package.swift", "Package.resolved", "Sources", WORKFLOW, SCRIPT], cwd=root)
    require(not tracked, "native-source inputs are not the checked-out revision")
    output = root / ".build/release"
    binary = output / "tlc-validate"
    if sys.argv[1] == "capture":
        expansions = list((Path(tempfile.gettempdir()) / "swift-generated-sources").glob(EXPANSION))
        require(len(expansions) == 1, "expected one compiler expansion for the existing pilot")
        origin = {"repository": os.environ["GITHUB_REPOSITORY"], "runID": os.environ["GITHUB_RUN_ID"],
                  "attempt": os.environ["GITHUB_RUN_ATTEMPT"], "job": os.environ["GITHUB_JOB"]}
        capture(root, binary, expansions[0], output, int(sys.argv[2]), origin)
    receipt = verify(root, binary, output)
    print(json.dumps({"producerSHA": receipt["producerSHA"], "sourceSHA256": receipt["sourceSHA256"],
                      "binarySHA256": receipt["binarySHA256"], "origin": receipt["origin"],
                      "semanticInterpretation": "OPEN"}))


if __name__ == "__main__":
    main()
