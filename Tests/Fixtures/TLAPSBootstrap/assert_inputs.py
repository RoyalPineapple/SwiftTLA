#!/usr/bin/env python3
import hashlib
import json
import os
from pathlib import Path
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
