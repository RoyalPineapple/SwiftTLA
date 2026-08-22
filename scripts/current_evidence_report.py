#!/usr/bin/env python3
from hashlib import sha256
from pathlib import Path
import json
import sys


def report_reference(root: Path) -> Path:
    return root / "current-support-admission.json"


def resolve(root: Path) -> Path:
    value = json.loads(report_reference(root).read_text())
    report = (root / value["path"]).resolve()
    if not report.is_relative_to(root) or sha256(report.read_bytes()).hexdigest() != value["sha256"]:
        raise ValueError("invalid current report reference")
    return report


def write(root: Path, report: Path) -> None:
    report = report.resolve()
    if not report.is_relative_to(root):
        raise ValueError("report is outside output root")
    report_reference(root).write_text(json.dumps({
        "path": str(report.relative_to(root)),
        "sha256": sha256(report.read_bytes()).hexdigest(),
    }, separators=(",", ":")) + "\n")


def main(arguments: list[str]) -> None:
    if arguments[:1] == ["write"] and len(arguments) == 3:
        write(Path(arguments[1]).resolve(), Path(arguments[2]))
    elif arguments[:1] == ["resolve"] and len(arguments) == 2:
        print(resolve(Path(arguments[1]).resolve()))
    else:
        raise ValueError("usage: current_evidence_report.py write <root> <report> | resolve <root>")


try:
    main(sys.argv[1:])
except (OSError, KeyError, TypeError, ValueError, json.JSONDecodeError) as error:
    raise SystemExit(f"current evidence report: {error}")
