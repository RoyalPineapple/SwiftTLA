#!/usr/bin/env python3
"""Run selected obligations from a retained actual initialization proof packet.

Invoked by local-validation.sh under its exclusive lock and memory watchdog.
Results are diagnostic: referenced facts and unselected dependencies are not checked.
"""
import difflib
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load_byte_input(source, directory, pages, prefix="CompilerInput"):
    """Exact-byte ingress only; no selection, lexing, decoding or interpretation."""
    if prefix not in {"CompilerInput", "CallerInput"}:
        raise ValueError("unknown byte-input namespace")
    data = source.read_bytes()
    retained = directory / ("compiler-input.bin" if prefix == "CompilerInput" else "caller-input.bin")
    module = directory / f"{prefix}Bytes.tla"
    # Page numbers address bytes, not functions or instructions. Missing pages have no default.
    page_size = 16
    pages = sorted(set(pages))
    if any(type(page) is not int or not 1 <= page <= (len(data) + page_size - 1) // page_size
           for page in pages):
        raise ValueError("requested byte page is outside the actual input")
    lines = [f"---- MODULE {prefix}Bytes ----", "EXTENDS Integers",
             f"CONSTANT {prefix}Byte", f"{prefix}Size == {len(data)}",
             f"{prefix}PageSize == {page_size}",
             "\\* External exact-byte input facts only; no source-selection or semantic premises.",
             f"ASSUME {prefix}Domain == DOMAIN {prefix}Byte = 0..({prefix}Size - 1)"]
    blocks = {}
    for page in pages:
        block = (page - 1) // 64 + 1
        if block not in blocks:
            blocks[block] = []
        offset = (page - 1) * page_size
        values = ", ".join(map(str, data[offset:offset + page_size]))
        count = min(page_size, len(data) - offset)
        blocks[block].append((page, offset, count, values))
    lines.append("====")
    with retained.open("xb") as stream:
        stream.write(data)
    with module.open("x") as stream:
        stream.write("\n".join(lines) + "\n")
    page_modules = []
    for block, entries in blocks.items():
        name = f"{prefix}PageBlock{block}"
        body = [f"---- MODULE {name} ----", f"EXTENDS {prefix}Bytes",
                f"ASSUME {name}AtFileOffsets =="]
        body += [f"    /\\ \\A j \\in 1..{count}: {prefix}Byte[{offset} + j - 1] = <<{values}>>[j]"
                 for _, offset, count, values in entries]
        path = directory / f"{name}.tla"
        with path.open("x") as stream:
            stream.write("\n".join(body + ["===="]) + "\n")
        page_modules.append({"path": str(path), "sha256": digest(path)})
    return {"foundation": "USER_AUTHORIZED_EXACT_BYTE_LOADING_ONLY",
            "namespace": prefix, "path": str(source), "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest(),
            "retainedPath": str(retained), "modulePath": str(module),
            "moduleSHA256": digest(module), "pageSize": page_size, "loadedPages": pages,
            "pageModules": page_modules,
            "indexContract": "Each loaded tuple element j equals file[pageOffset + j - 1]; missing pages have no facts",
            "semanticTransformationsChecked": False}


def copy_proof_imports(candidate, target, reserved):
    """Retain explicit sibling module bytes; importing a theorem does not check its proof."""
    directory = candidate.with_suffix(".imports")
    if not directory.exists():
        return []
    if directory.is_symlink() or not directory.is_dir():
        raise ValueError("proof imports must be a real directory")
    sources = sorted(directory.iterdir())
    for source in sources:
        if (source.is_symlink() or not source.is_file() or source.suffix != ".tla"
                or source.name in reserved or re.fullmatch(r"(?:CompilerInput|CallerInput)PageBlock[0-9]+\.tla", source.name)
                or (target / source.name).exists()):
            raise ValueError("invalid or shadowing proof import: " + source.name)
        header = re.search(rb"^-+ MODULE ([A-Za-z_][A-Za-z_0-9]*) -+", source.read_bytes())
        if not header or header[1].decode() != source.stem:
            raise ValueError("proof import filename/module mismatch: " + source.name)
    receipts = []
    for source in sources:
        retained = target / source.name
        with retained.open("xb") as stream:
            stream.write(source.read_bytes())
        receipts.append({"path": str(source), "retainedPath": str(retained), "sha256": digest(retained),
                         "proofCheckedByThisInvocation": False})
    return receipts


def selected_result(log, first, last, exit_code):
    events = []
    for block in re.findall(r"@!!BEGIN\n(.*?)@!!END", log, re.S):
        header = block.split("@!!obl:", 1)[0]
        fields = dict(re.findall(r"^@!!([^:\n]+):(.*)$", header, re.M))
        if fields.get("type") == "obligation":
            events.append(fields)
    declared = {e["id"]: e for e in events if e.get("status") == "to be proved"}
    final = {e["id"]: e for e in events if e.get("status") in ["proved", "trivial", "failed"]}
    selected = bool(declared) and all(first <= int(e["loc"].split(":")[0]) <=
                                     int(e["loc"].split(":")[2]) <= last for e in declared.values())
    passed = (exit_code == 0 and selected and declared.keys() == final.keys()
              and all(e["status"] in ["proved", "trivial"] and e.get("already") == "false"
                      and e["loc"] == declared[key]["loc"] for key, e in final.items())
              and "[ERROR]" not in log and "\0" not in log)
    return {"selectedIntendedRange": selected, "declared": declared, "final": final,
            "status": "FOCUSED_PASS_DEPENDENCIES_UNCHECKED" if passed else "FOCUSED_NOT_PROVED"}


def main():
    if not 4 <= len(sys.argv) <= 7:
        raise ValueError("expected packet, line range, optional candidate and helper/caller byte inputs")
    root = Path.cwd()
    packet = Path(sys.argv[1]).resolve(strict=True)
    first, last = map(int, sys.argv[2:4])
    original = packet / "case/generated-tla/SwiftTLAInitialFailureProof.tla"
    candidate = Path(sys.argv[4]).resolve(strict=True) if len(sys.argv) >= 5 else original
    byte_source = Path(sys.argv[5]).resolve(strict=True) if len(sys.argv) >= 6 else None
    caller_byte_source = Path(sys.argv[6]).resolve(strict=True) if len(sys.argv) == 7 else None
    preparation = json.loads((packet / "case/preparation.json").read_text())
    bindings = {
        "proofSHA256": original,
        "moduleSHA256": packet / "case/generated-tla" / (preparation["module"] + ".tla"),
        "checkModuleSHA256": packet / "case/generated-tla" / (preparation["checkModule"] + ".tla"),
        "checkConfigurationSHA256": packet / "case/generated-tla" / (preparation["checkModule"] + ".cfg"),
        "nativeSHA256": packet / "case/native-initial-failure.json",
        "nativeSourceSHA256": packet / "case/native-initial-source.swift",
    }
    if "authoredSourceSHA256" in preparation or "actionSourceSHA256" in preparation:
        bindings.update(authoredSourceSHA256=packet / "case/authored-model.swift",
                        actionSourceSHA256=packet / "case/generated-tla/SwiftTLAStayActionSource.tla")
    for field, path in bindings.items():
        if digest(path) != preparation[field]:
            raise ValueError(f"retained packet mismatch: {field}")
    if (packet / "source-sha.txt").read_text().strip() != preparation["sourceSHA"]:
        raise ValueError("retained packet source revision mismatch")
    for line in (packet / "proof-inputs.sha256").read_text().splitlines():
        expected, name = line.split(maxsplit=1)
        path = packet / "proof-inputs" / Path(name).name
        if digest(path) != expected:
            raise ValueError(f"retained import mismatch: {path.name}")
    for name in ["proof-toolchain.json", "packaging.patch"]:
        source = root / ("Verification/Semantics" if name.endswith(".json") else "Tools/TLAPS") / name
        if source.read_bytes() != (packet / "toolchain/build-inputs" / name).read_bytes():
            raise ValueError(f"current tool input differs from retained packet: {name}")
    lines = candidate.read_text().splitlines(keepends=True)
    if not 1 <= first <= last <= len(lines):
        raise ValueError("selected lines are outside the candidate proof")
    common = Path(subprocess.check_output(["git", "rev-parse", "--git-common-dir"], text=True).strip()).resolve()
    parent = common / "swifttla-proof-evidence/focused-initialization"
    parent.mkdir(parents=True, exist_ok=True)
    output = Path(tempfile.mkdtemp(prefix=f"lines-{first}-{last}-", dir=parent))
    inputs = {str(p.relative_to(packet)): digest(p) for p in packet.rglob("*") if p.is_file()}
    receipt = {
        "scope": "FOCUSED_DIAGNOSTIC_ONLY", "completeModuleProved": False,
        "wholeOriginalModuleSelected": first == 1 and last == len(lines) and candidate.read_bytes() == original.read_bytes(),
        "packet": str(packet), "sourceSHA": preparation["sourceSHA"],
        "inputSHA256": inputs, "candidateSHA256": digest(candidate),
        "selectedLines": [first, last], "selectedText": "".join(lines[first - 1:last]),
        "originalProofSHA256": digest(original), "output": str(output),
    }
    (output / "request.json").write_text(json.dumps(receipt, indent=2) + "\n")
    (output / "candidate.diff").write_text("".join(difflib.unified_diff(
        original.read_text().splitlines(keepends=True), lines,
        fromfile="retained/SwiftTLAInitialFailureProof.tla", tofile="candidate/SwiftTLAInitialFailureProof.tla")))
    print(f"Focused diagnostic evidence: {output}", flush=True)
    tool = root / ".build/pinned-tlaps"
    executable = tool / "tlapm/bin/tlapm"
    if not executable.is_file():
        receipt["status"] = "PINNED_RUNTIME_MISSING_NO_OBLIGATIONS_EXECUTED"
        (output / "result.json").write_text(json.dumps(receipt, indent=2) + "\n")
        print("Pinned TLAPS runtime is missing; no compiler build or proof was started.", file=sys.stderr)
        return 64
    pin = json.loads((root / "Verification/Semantics/proof-toolchain.json").read_text())
    identity_paths = ["Verification/Semantics/proof-toolchain.json", "Tools/TLAPS/packaging.patch",
                      "scripts/build-pinned-tlaps.sh", "scripts/verify-tlaps-build-inputs.py",
                      ".github/actions/setup-pinned-tlaps/action.yml"]
    identity = hashlib.sha256("".join(f"{digest(root / p)}  {root / p}\n" for p in identity_paths).encode()).hexdigest()
    if (tool / "build-record/identity.txt").read_text().strip() != identity:
        raise ValueError("pinned tool build identity mismatch")
    with (output / "tool-integrity.log").open("w") as integrity:
        subprocess.run(["shasum", "-a", "256", "-c", "contents.sha256"], cwd=tool,
                       stdout=integrity, check=True)
    version = subprocess.check_output([str(executable), "--version"], text=True).strip()
    z3 = subprocess.check_output([str(tool / "tlapm/lib/tlapm/backends/bin/z3"), "--version"], text=True).strip()
    if version not in [pin["sourceRevision"], pin["sourceRevision"] + "-dirty"] or z3 != "Z3 version 4.15.4 - 64 bit":
        raise ValueError("pinned TLAPS/Z3 version mismatch")
    work = output / "packet"
    shutil.copytree(packet, work)
    module = re.search(r"^-+ MODULE ([A-Za-z_][A-Za-z_0-9]*) -+", candidate.read_text())
    if not module:
        raise ValueError("candidate has no TLA module header")
    target = work / original.relative_to(packet).parent / (module[1] + ".tla")
    target.write_bytes(candidate.read_bytes())
    reserved = {p.name for p in (tool / "tlapm/lib/tlapm").rglob("*.tla")}
    reserved.update(p.name for p in work.rglob("*.tla"))
    reserved.update({"CompilerInputBytes.tla", "CallerInputBytes.tla"})
    receipt["additionalProofInputs"] = copy_proof_imports(candidate, target.parent, reserved)
    texts = [candidate.read_text()] + [Path(item["retainedPath"]).read_text()
                                       for item in receipt["additionalProofInputs"]]
    for prefix, source, key in [("CompilerInput", byte_source, "byteInput"),
                                ("CallerInput", caller_byte_source, "callerByteInput")]:
        if source is None:
            continue
        if list(work.rglob(f"{prefix}Bytes.tla")):
            raise ValueError("retained packet or candidate shadows the byte-input module")
        pages = {int(page) for text in texts
                 for page in re.findall(rf"\b{prefix}Page([0-9]+)(?:AtFileOffsets)?\b", text)}
        receipt[key] = load_byte_input(source, target.parent, pages, prefix)
    (output / "request.json").write_text(json.dumps(receipt, indent=2) + "\n")
    command = [str(executable), "--strict", "--nofp", "--timing", "--toolbox", str(first), str(last),
               "--toolbox-vsn", "1", "--debug", "tempfiles",
               "-I", str(work / "proof-inputs"), str(target)]
    receipt.update(command=command, tlapmVersion=version, z3Version=z3)
    with (output / "proof.log").open("wb") as log:
        result = subprocess.run(command, cwd=work, stdin=subprocess.DEVNULL,
                                stdout=log, stderr=subprocess.STDOUT)
    log = (output / "proof.log").read_text()
    receipt.update(selected_result(log, first, last, result.returncode),
                   exitCode=result.returncode, proofLogSHA256=digest(output / "proof.log"))
    receipt["completeModuleProved"] = (receipt["wholeOriginalModuleSelected"]
                                      and receipt["status"] == "FOCUSED_PASS_DEPENDENCIES_UNCHECKED")
    if receipt["wholeOriginalModuleSelected"]:
        receipt["scope"] = "FULL_GENERATED_MODULE_DIAGNOSTIC_IMPORT_PROOFS_EXTERNAL_NOT_ADMISSION"
    if any(digest(packet / name) != sha for name, sha in inputs.items()):
        raise ValueError("retained packet changed during focused check")
    if digest(candidate) != receipt["candidateSHA256"] or digest(target) != receipt["candidateSHA256"]:
        raise ValueError("candidate changed during focused check")
    for item in receipt["additionalProofInputs"]:
        if digest(Path(item["path"])) != item["sha256"] or digest(Path(item["retainedPath"])) != item["sha256"]:
            raise ValueError("proof import changed during focused check")
    if byte_source is not None:
        binding = receipt["byteInput"]
        if (digest(byte_source) != binding["sha256"]
                or digest(Path(binding["retainedPath"])) != binding["sha256"]
                or digest(Path(binding["modulePath"])) != binding["moduleSHA256"]
                or any(digest(Path(item["path"])) != item["sha256"] for item in binding["pageModules"])):
            raise ValueError("byte input changed during focused check")
    (output / "result.json").write_text(json.dumps(receipt, indent=2) + "\n")
    print(receipt["status"], flush=True)
    return 0 if receipt["status"] == "FOCUSED_PASS_DEPENDENCIES_UNCHECKED" else 1


if __name__ == "__main__":
    sys.exit(main())
