"""Recreate the two exact byte inputs for the retained scheduler proof."""

from hashlib import sha256
from pathlib import Path
import subprocess
import sys


REVISION = "06c0987ea7d4ecc43b17711c53b1653d30af6410"
ROOT = Path(__file__).resolve().parents[3]


def current(name):
    path = ROOT / "Sources/SwiftTLA" / name
    data = path.read_bytes()
    if data != historical(path.relative_to(ROOT)):
        raise ValueError(f"source used by the proof changed: {name}")
    return data


def historical(path):
    return subprocess.check_output(["git", "-C", ROOT, "cat-file", "blob", f"{REVISION}:{path}"])


def main(destination):
    # Fixed file origins are part of the checked byte-address expressions.
    compiler = b"".join((
        current("AlgorithmModel.swift").ljust(39936, b"\0"),
        current("CompiledLowerer.swift").ljust(185344 - 39936, b"\0"),
        current("AlgorithmLowering.swift").ljust(252928 - 185344, b"\0"),
        historical("Sources/SwiftTLA/CompiledTypeChecker.swift"),
    ))
    # The trailing source files reproduce the original container. Scheduler
    # theorems only use caller pages inside StateExpr+Substitution.swift.
    caller = current("StateExpr+Substitution.swift") + b"".join(historical(path) for path in (
        "Sources/SwiftTLA/CompiledExpressions.swift",
        "Sources/SwiftTLA/ProgramResolver.swift",
        "Sources/SwiftTLA/CompiledTLARenderer.swift",
        "Sources/SwiftTLAPlugin/NativeSwiftEmitter+Machine.swift",
    ))
    if compiler.count(b"lower(scheduled,") != 1:
        raise ValueError("expected exactly one lower call using scheduled")
    wrong = compiler.replace(b"lower(scheduled,", b"lower(step.model.statements,", 1)
    inputs = (
        ("compiler.bin", compiler, "bed3490919ddc317145e6ac61aca733039b105123f75d6cf61b7130aeb4c5924"),
        ("caller.bin", caller, "5f45f2c2614c8118628cfa45a3cbd54c85b4954cdd1d7f2443d534f284c6f924"),
        ("authored-argument.bin", wrong, "6baaa41e06b6ad7f49b189d4a7b26e5061b51581dc2606e82dfd3dbefa19de09"),
    )
    for name, data, expected in inputs:
        if sha256(data).hexdigest() != expected:
            raise ValueError(f"input digest mismatch: {name}")
    destination.mkdir()
    for name, data, _ in inputs:
        (destination / name).write_bytes(data)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("usage: prepare-inputs.py NEW_DIRECTORY")
    main(Path(sys.argv[1]))
