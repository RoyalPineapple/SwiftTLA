#!/usr/bin/env python3
import hashlib
import json
from pathlib import Path
import re
import sys


def verified_inputs(lock_path, patch_path):
    pin = json.loads(Path(lock_path).read_text())
    patch = Path(patch_path).read_bytes()
    if not isinstance(pin, dict) or pin.get("schema") != "PinnedTLAPSBuild":
        raise ValueError("unsupported proof-tool pin schema")
    for field in ("sourceCommit", "opamRepositoryCommit"):
        if not re.fullmatch(r"[0-9a-f]{40}", pin.get(field, "")):
            raise ValueError(f"{field} must be a full immutable commit")
    if pin.get("sourceRevision") != pin["sourceCommit"][:7]:
        raise ValueError("proof-tool version does not match its source commit")
    if not re.fullmatch(r"ocaml-base-compiler\.\d+\.\d+\.\d+", pin.get("ocamlCompiler", "")):
        raise ValueError("OCaml compiler must be an exact package version")
    if pin.get("z3Version") != "4.15.4":
        raise ValueError("this proof batch requires Z3 4.15.4")
    if hashlib.sha256(patch).hexdigest() != pin.get("packagingPatchSHA256"):
        raise ValueError("proof packaging patch does not match its pin")
    paths = re.findall(r"^diff --git a/(\S+) b/(\S+)$", patch.decode(), re.MULTILINE)
    expected = {"library/dune", "deps/z3/Makefile", "deps/ls4/Makefile"}
    if len(paths) != len(expected) or {a for a, b in paths if a == b} != expected:
        raise ValueError("proof packaging may only change dependency downloads")
    return pin


if __name__ == "__main__":
    try:
        if len(sys.argv) != 3:
            raise ValueError("usage: verify-tlaps-build-inputs.py <pin> <packaging-patch>")
        print(json.dumps(verified_inputs(*sys.argv[1:]), sort_keys=True))
    except (OSError, ValueError, KeyError, TypeError) as error:
        sys.exit(f"proof-tool pin: {error}")
