#!/usr/bin/env python3
import hashlib
import json
import os
from pathlib import Path
import re
import runpy
import subprocess
import sys
import tempfile


root = Path(__file__).resolve().parents[3]
validator = root / "scripts/verify-tlaps-build-inputs.py"
original_pin = json.loads((root / "Verification/Semantics/proof-toolchain.json").read_text())
original_patch = (root / "Tools/TLAPS/packaging.patch").read_bytes()

with tempfile.TemporaryDirectory(prefix="swifttla-proof-pin-") as directory:
    pin_file = Path(directory) / "pin.json"
    patch_file = Path(directory) / "packaging.patch"

    def check(pin, patch, expected_error=None):
        pin_file.write_text(json.dumps(pin))
        patch_file.write_bytes(patch)
        result = subprocess.run(
            [sys.executable, str(validator), str(pin_file), str(patch_file)],
            capture_output=True, text=True,
        )
        if expected_error is None:
            assert result.returncode == 0, result.stderr
            assert json.loads(result.stdout) == original_pin
        else:
            assert result.returncode != 0, "invalid proof build inputs were accepted"
            assert expected_error in result.stderr, result.stderr

    check(original_pin, original_patch)
    for field, wrong, reason in [
        ("sourceCommit", "main", "full immutable commit"),
        ("opamRepositoryCommit", "master", "full immutable commit"),
        ("sourceRevision", "0000000", "does not match its source commit"),
        ("ocamlCompiler", "5.5.x", "exact package version"),
        ("packagingPatchSHA256", "0" * 64, "does not match its pin"),
    ]:
        check(dict(original_pin, **{field: wrong}), original_patch, reason)

    changed_patch = original_patch.replace(b"library/dune", b"src/params.ml")
    changed_pin = dict(original_pin,
        packagingPatchSHA256=hashlib.sha256(changed_patch).hexdigest())
    check(changed_pin, changed_patch, "may only change dependency downloads")

# Unmodified deps/isabelle/dune.mk from the pinned TLAPM source commit.
with tempfile.TemporaryDirectory(prefix="swifttla-isabelle-download-") as directory:
    work = Path(directory)
    recipe = work / "deps/isabelle/dune.mk"
    recipe.parent.mkdir(parents=True)
    recipe.write_bytes((Path(__file__).parent / "isabelle.dune.mk").read_bytes())
    subprocess.run(
        ["git", "apply", "--allow-empty", "--include=deps/isabelle/dune.mk",
         str(root / "Tools/TLAPS/packaging.patch")],
        cwd=work, check=True, capture_output=True, text=True,
    )
    tools = work / "bin"
    tools.mkdir()
    wget = tools / "wget"
    wget.write_text("""#!/usr/bin/env python3
import os
from pathlib import Path
import sys

calls = Path(os.environ["DOWNLOAD_CALLS"])
attempt = int(calls.read_text()) + 1 if calls.exists() else 1
calls.write_text(str(attempt))
args = sys.argv[1:]
assert "--no-check-certificate" not in args
url = "https://isabelle.in.tum.de/website-Isabelle2025/dist/Isabelle2025_macos.tar.gz"
assert url in args
if "-O" in args:
    target = Path(args[args.index("-O") + 1])
else:
    prefix = next(arg.split("=", 1)[1] for arg in args if arg.startswith("--directory-prefix="))
    target = Path(prefix) / "Isabelle2025_macos.tar.gz"
    assert not target.exists(), "partial download would be saved under a different filename"
if attempt <= int(os.environ["DOWNLOAD_FAILURES"]):
    target.write_bytes(b"partial download")
    sys.exit(4)
target.write_bytes(os.environ["DOWNLOAD_BYTES"].encode())
""")
    wget.chmod(0o755)
    sleep = tools / "sleep"
    sleep.write_text("#!/bin/sh\nexit 0\n")
    sleep.chmod(0o755)
    cache = work / "cache"
    cache.mkdir()
    archive = cache / "Isabelle2025_macos.tar.gz"
    calls = work / "calls"
    payload = b"verified archive bytes"
    for name, failures, downloaded, cached, expected_calls, success in [
        ("transient TLS failure", 2, payload, None, 3, True),
        ("persistent network failure", 99, payload, None, 3, False),
        ("wrong archive checksum", 0, b"corrupt archive", None, 1, False),
        ("verified cache hit", 99, payload, payload, 0, True),
        ("stale partial archive", 1, payload, b"partial download", 2, True),
    ]:
        archive.unlink(missing_ok=True)
        calls.unlink(missing_ok=True)
        if cached is not None:
            archive.write_bytes(cached)
        result = subprocess.run(
            ["make", "-f", str(recipe), str(archive), f"CACHE_DIR={cache}",
             "OS_TYPE=Darwin", f"ISABELLE_SHA256={hashlib.sha256(payload).hexdigest()}"],
            cwd=work, capture_output=True, text=True, timeout=10,
            env=dict(os.environ, PATH=str(tools) + os.pathsep + os.environ["PATH"],
                     DOWNLOAD_CALLS=str(calls), DOWNLOAD_FAILURES=str(failures),
                     DOWNLOAD_BYTES=downloaded.decode()),
        )
        actual_calls = int(calls.read_text()) if calls.exists() else 0
        assert actual_calls == expected_calls, f"{name}: {actual_calls} download attempts, expected {expected_calls}"
        assert (result.returncode == 0) == success, f"{name}: {result.stdout}\n{result.stderr}"
        if success:
            assert archive.read_bytes() == payload, name
        elif name == "wrong archive checksum":
            assert f"{archive}: FAILED" in result.stdout, result.stdout
        print(f"Isabelle download: {name}: {actual_calls} attempts, {'accepted' if success else 'rejected'}")

print("Proof build pins, packaging boundary, and Isabelle download controls passed.")

# A zero exit status alone cannot establish a nonempty, uncached selected proof.
proof_runner = runpy.run_path(str(root / "scripts/check-initial-proof-step.py"))
selected_result = proof_runner["selected_result"]
declared = """@!!BEGIN
@!!type:obligation
@!!id:136
@!!loc:257:5:257:7
@!!status:to be proved
@!!END
"""
proved = """@!!BEGIN
@!!type:obligation
@!!id:136
@!!loc:257:5:257:7
@!!status:proved
@!!already:false
@!!END
"""
for name, protocol, exit_code, expected in [
    ("selected uncached completion", declared + proved, 0, True),
    ("empty selection", "All 0 obligations proved\n", 0, False),
    ("unfinished selection", declared, 0, False),
    ("different obligation", declared + proved.replace("id:136", "id:137"), 0, False),
    ("wrong range", (declared + proved).replace("257:", "258:"), 0, False),
    ("moved final span", declared + proved.replace("257:", "258:"), 0, False),
    ("cached result", declared + proved.replace("already:false", "already:true"), 0, False),
    ("failed backend", declared + proved.replace("status:proved", "status:failed"), 0, False),
    ("failed process", declared + proved, 10, False),
    ("tool error", declared + proved + "[ERROR] incomplete proof\n", 0, False),
]:
    result = selected_result(protocol, 257, 257, exit_code)
    assert (result["status"] == "FOCUSED_PASS_DEPENDENCIES_UNCHECKED") == expected, name
print("Focused proof selection/status controls passed (no mathematical proof credit).")

# The input boundary preserves arbitrary bytes and page order, without text decoding.
with tempfile.TemporaryDirectory(prefix="swifttla-proof-byte-input-") as directory:
    work = Path(directory)
    source = work / "actual-input"
    for index, payload in enumerate([b"", bytes(range(256)) * 5 + b"\r\n\x00\xff", b"br bb14\n"]):
        source.write_bytes(payload)
        output = work / str(index)
        output.mkdir()
        requested = list(range(1, (len(payload) + 15) // 16 + 1))
        receipt = proof_runner["load_byte_input"](source, output, reversed(requested))
        assert Path(receipt["retainedPath"]).read_bytes() == payload
        text = Path(receipt["modulePath"]).read_text()
        assert not re.search(r"^CompilerInputPage[0-9]+ ==", text, re.M)
        for item in receipt["pageModules"]:
            path = Path(item["path"])
            assert hashlib.sha256(path.read_bytes()).hexdigest() == item["sha256"]
            block = int(re.fullmatch(r"CompilerInputPageBlock([0-9]+)\.tla", path.name)[1])
            content = path.read_text()
            assert f"MODULE CompilerInputPageBlock{block} ----\nEXTENDS CompilerInputBytes\n" in content
            assert all(int(offset) // 1024 + 1 == block
                       for offset in re.findall(r"CompilerInputByte\[([0-9]+) \+ j - 1\]", content))
            text += content
        pages = re.findall(r"\\A j \\in 1\.\.([0-9]+): CompilerInputByte\[([0-9]+) \+ j - 1\] = <<([0-9, ]+)>>\[j\]", text)
        assert [(int(count), int(offset)) for count, offset, _ in pages] == [
            (min(16, len(payload) - (page - 1) * 16), (page - 1) * 16) for page in requested]
        assert all(int(count) == len(values.split(",")) for count, _, values in pages)
        decoded = b"".join(bytes(int(value) for value in values.split(",")) for _, _, values in pages)
        assert decoded == payload, "byte loading changed input data or page order"
        assert int(re.search(r"^CompilerInputSize == ([0-9]+)$", text, re.M)[1]) == len(payload)
        assert receipt["sha256"] == hashlib.sha256(payload).hexdigest()
        assert receipt["semanticTransformationsChecked"] is False
        try:
            proof_runner["load_byte_input"](source, output, requested)
        except FileExistsError:
            pass
        else:
            raise AssertionError("byte input overwrote an existing proof packet")
    source.write_bytes(bytes(range(256)) * 5)
    sparse = work / "sparse"
    sparse.mkdir()
    receipt = proof_runner["load_byte_input"](source, sparse, [66, 1, 65, 66])
    pages = re.findall(r"CompilerInputByte\[([0-9]+) \+ j - 1\] = <<([0-9, ]+)>>\[j\]",
                       "\n".join(Path(item["path"]).read_text() for item in receipt["pageModules"]), re.M)
    assert [int(offset) for offset, _ in pages] == [0, 1024, 1040]
    assert [bytes(int(value) for value in values.split(",")) for _, values in pages] == [
        bytes(range(16)), bytes(range(16)), bytes(range(16, 32))]
    for requested in [[0], [81]]:
        try:
            proof_runner["load_byte_input"](source, work / "invalid", requested)
        except ValueError:
            pass
        else:
            raise AssertionError("out-of-range byte address was accepted")
# Distinct files may disagree at the same address; their assumptions must stay separate.
with tempfile.TemporaryDirectory(prefix="swifttla-proof-two-inputs-") as directory:
    work = Path(directory)
    first, second = work / "helper", work / "caller"
    first.write_bytes(b"\x00\xff")
    second.write_bytes(b"\xff\x00\x0a")
    helper = proof_runner["load_byte_input"](first, work, [1])
    helper_files = [Path(helper["modulePath"]), Path(helper["retainedPath"])] + [
        Path(item["path"]) for item in helper["pageModules"]]
    preserved = {path: path.read_bytes() for path in helper_files}
    caller = proof_runner["load_byte_input"](second, work, [1], "CallerInput")
    assert all(path.read_bytes() == data for path, data in preserved.items())
    assert Path(caller["retainedPath"]).read_bytes() == b"\xff\x00\x0a"
    assert Path(caller["retainedPath"]) != Path(helper["retainedPath"])
    text = Path(caller["modulePath"]).read_text()
    assert "CONSTANT CallerInputByte\n" in text and "CallerInputSize == 3\n" in text
    text += "".join(Path(item["path"]).read_text() for item in caller["pageModules"])
    assert "CompilerInput" not in text
    assert "CallerInputByte[0 + j - 1] = <<255, 0, 10>>[j]" in text
    try:
        proof_runner["load_byte_input"](second, work, [1], "Other")
    except ValueError:
        pass
    else:
        raise AssertionError("unrecognized byte-input namespace accepted")
print("Exact-byte proof input controls passed (external input foundation, not semantic proof).")

with tempfile.TemporaryDirectory(prefix="swifttla-proof-imports-") as directory:
    work = Path(directory)
    candidate = work / "Parent.tla"
    imports = candidate.with_suffix(".imports")
    imports.mkdir()
    target = work / "retained"
    target.mkdir()
    source = imports / "Child.tla"
    payload = "---- MODULE Child ----\r\n\\* τ remains UTF-8\r\n====\r\n".encode()
    source.write_bytes(payload)
    receipts = proof_runner["copy_proof_imports"](candidate, target, {"CompilerInputBytes.tla"})
    assert len(receipts) == 1 and Path(receipts[0]["retainedPath"]).read_bytes() == payload
    assert receipts[0]["sha256"] == hashlib.sha256(payload).hexdigest()
    assert receipts[0]["proofCheckedByThisInvocation"] is False
    for name, contents, reserved, symlink in [
        ("Child.tla", payload, set(), False),  # Cannot overwrite the retained copy.
        ("CompilerInputBytes.tla", b"---- MODULE CompilerInputBytes ----\n====\n", {"CompilerInputBytes.tla"}, False),
        ("CompilerInputPageBlock1.tla", b"---- MODULE CompilerInputPageBlock1 ----\n====\n", set(), False),
        ("CallerInputBytes.tla", b"---- MODULE CallerInputBytes ----\n====\n", {"CallerInputBytes.tla"}, False),
        ("CallerInputPageBlock1.tla", b"---- MODULE CallerInputPageBlock1 ----\n====\n", set(), False),
        ("Alias.tla", payload, set(), False),
        ("Link.tla", payload, set(), True),
    ]:
        for path in imports.iterdir():
            path.unlink()
        proposed = imports / name
        if symlink:
            proposed.symlink_to(target / "Child.tla")
        else:
            proposed.write_bytes(contents)
        try:
            proof_runner["copy_proof_imports"](candidate, target, reserved)
        except ValueError:
            pass
        else:
            raise AssertionError("unsafe proof import accepted: " + name)
        assert list(target.iterdir()) == [target / "Child.tla"]
        assert (target / "Child.tla").read_bytes() == payload
print("Proof import byte retention and shadowing controls passed (imported proofs remain unchecked).")
