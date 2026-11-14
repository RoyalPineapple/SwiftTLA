#!/usr/bin/env python3
"""Retain fresh actual pilot outputs after the guarded focused consumer check."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import time


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def payloads(root):
    names = subprocess.check_output(["git", "ls-files", "-z"], cwd=root).decode().split("\0")[:-1]
    return {name: hashlib.sha256(os.readlink(root / name).encode() if (root / name).is_symlink()
                                else (root / name).read_bytes()).hexdigest() for name in names}


def main():
    root = Path.cwd()
    scratch = Path(sys.argv[1]).resolve(strict=True)
    guarded_scratch = os.environ.get("SWIFTTLA_VALIDATION_SCRATCH_PATH")
    if not guarded_scratch or not scratch.samefile(guarded_scratch):
        raise ValueError("invoke through local-validation.sh proof-prepare")
    common = Path(subprocess.check_output(["git", "rev-parse", "--git-common-dir"], text=True).strip()).resolve()
    output = Path(sys.argv[2]).resolve()
    expected = Path(sys.argv[3]).resolve(strict=True)
    if not output.is_relative_to(common / "swifttla-proof-evidence") or output.exists():
        raise ValueError("output must be a new proof-evidence directory")
    if subprocess.check_output(["git", "status", "--porcelain", "--untracked-files=all"]):
        raise ValueError("fresh packet requires a clean committed source revision")
    head = subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip()
    inputs = payloads(root)
    output.mkdir(parents=True)
    expected_bytes = expected.read_bytes()
    (output / "checked-proof.tla").write_bytes(expected_bytes)
    receipt = {"scope": "LOCAL_DIAGNOSTIC_NOT_ADMISSION", "sourceSHA": head, "inputs": inputs,
               "expectedProofSHA256": hashlib.sha256(expected_bytes).hexdigest(),
               "mathematicalProof": False, "hostedAdmission": False}
    (output / "inputs.json").write_text(json.dumps(receipt, indent=2) + "\n")
    print(f"Fresh compiler diagnostic evidence: {output}", flush=True)
    try:
        build = scratch / "build"
        started = time.time_ns()
        command = ["swift", "test", "-Xswiftc", "-warnings-as-errors", "-Xswiftc", "-g",
                   "--disable-automatic-resolution", "--filter", "InitialFailureEvidenceTests", "-j", "1",
                   "--scratch-path", str(build)]
        receipt["consumerCommand"] = command
        with (output / "consumer.log").open("wb") as log:
            run = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT)
        receipt["consumerExit"] = run.returncode
        log = (output / "consumer.log").read_text()
        counts = re.findall(r"Test run with (\d+) tests?.*passed", log)
        if run.returncode or not counts or int(counts[-1]) == 0 or "\0" in log:
            raise ValueError("focused compiler consumer did not complete a nonempty passing test run")
        receipt["actualConsumerTests"] = int(counts[-1])
        binary = (build / "debug/tlc-validate").resolve(strict=True)
        if not binary.is_relative_to(build):
            raise ValueError("validator is outside the fresh focused build")
        spec = importlib.util.spec_from_file_location("native_source", root / "scripts/retain-native-initial-source.py")
        native_source = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(native_source)
        expansions = [p for p in (Path(tempfile.gettempdir()) / "swift-generated-sources").glob(native_source.EXPANSION)
                      if p.stat().st_mtime_ns >= started]
        if len(expansions) != 1 or expansions[0].is_symlink():
            raise ValueError("expected exactly one fresh actual compiler expansion for the existing pilot")
        expansion = expansions[0]
        before = expansion.stat()
        data = expansion.read_bytes()
        after = expansion.stat()
        if (before.st_ino, before.st_size, before.st_mtime_ns) != (after.st_ino, after.st_size, after.st_mtime_ns):
            raise ValueError("compiler expansion changed while retaining it")
        original_range = native_source.source_range(data, root)
        retained = output / "native-initial-source.swift"
        retained.write_bytes(data)
        # A local receipt has no hosted run identity and cannot replace one.
        capture = {"schema": "swifttla.local-compiler-native-initial-source-v1", "sourceSHA": head,
                   "buildStartedEpochNS": started, "expansionModifiedEpochNS": before.st_mtime_ns,
                   "compilerExpansionName": expansion.name, "originalSourceRange": original_range,
                   "sourceSHA256": digest(retained), "binarySHA256": digest(binary),
                   "semanticInterpretation": "OPEN", "hostedAdmission": False}
        (output / "local-native-source.json").write_text(json.dumps(capture, indent=2) + "\n")
        packet = output / "packet"
        packet.mkdir()
        env = dict(os.environ, SWIFT_TLA_SHA=head)
        command = [str(binary), "initial-failure", "prepare", "--native-source", str(retained),
                   "--output", str(packet / "case")]
        receipt["prepareCommand"] = command
        with (output / "prepare.log").open("wb") as log:
            run = subprocess.run(command, env=env, stdout=log, stderr=subprocess.STDOUT)
        receipt["prepareExit"] = run.returncode
        if run.returncode:
            raise ValueError("actual validator preparation failed")
        preparation = json.loads((packet / "case/preparation.json").read_text())
        proof = packet / "case/generated-tla/SwiftTLAInitialFailureProof.tla"
        if preparation["sourceSHA"] != head or preparation["nativeSourceSHA256"] != digest(retained):
            raise ValueError("fresh producer/source capture binding differs")
        if proof.read_bytes() != expected_bytes or preparation["proofSHA256"] != digest(proof):
            raise ValueError("actual compiler did not emit the checked proof bytes exactly")
        imports = packet / "proof-inputs"
        imports.mkdir()
        names = ["OrderedIntExpressionRule", "IndexedHistoryRules", "InitializationOutcomeRules",
                 "InitializationComposition", "OrderedIntInitializationComposition", "FiniteSetMembershipRule"]
        for name in names:
            shutil.copyfile(root / f"Verification/Semantics/{name}.tla", imports / (name + ".tla"))
        (packet / "proof-inputs.sha256").write_text("".join(
            f"{digest(imports / (name + '.tla'))}  proof-inputs/{name}.tla\n" for name in names))
        tool_inputs = packet / "toolchain/build-inputs"
        tool_inputs.mkdir(parents=True)
        for name, directory in [("proof-toolchain.json", "Verification/Semantics"), ("packaging.patch", "Tools/TLAPS")]:
            shutil.copyfile(root / directory / name, tool_inputs / name)
        (packet / "source-sha.txt").write_text(head + "\n")
        shutil.copyfile(output / "local-native-source.json", packet / "local-native-source.json")
        if payloads(root) != inputs or subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip() != head:
            raise ValueError("source inputs changed during the guarded compiler check")
        receipt.update(status="FRESH_ACTUAL_PROOF_BYTES_MATCH_CHECKED_CANDIDATE", packet=str(packet),
                       allSourceInputsUnchanged=True, binarySHA256=capture["binarySHA256"],
                       actualProofSHA256=digest(proof), consumerLogSHA256=digest(output / "consumer.log"))
    except Exception as error:
        receipt.update(status="PREPARATION_NOT_VERIFIED_NO_MATHEMATICAL_CREDIT", error=str(error))
        raise
    finally:
        (output / "result.json").write_text(json.dumps(receipt, indent=2) + "\n")
    print(json.dumps({key: receipt[key] for key in ["status", "sourceSHA", "packet", "actualConsumerTests",
                                                  "actualProofSHA256", "mathematicalProof", "hostedAdmission"]}))


if __name__ == "__main__":
    main()
