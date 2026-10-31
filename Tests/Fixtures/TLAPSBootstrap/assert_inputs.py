#!/usr/bin/env python3
import hashlib
import json
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

print("Proof build pin and packaging-boundary negative controls passed.")
