#!/usr/bin/env python3
"""Run selected obligations from a retained actual initialization proof packet.

Invoked by local-validation.sh under its exclusive lock and memory watchdog.
Results are diagnostic: referenced facts and unselected dependencies are not checked.
"""
import difflib
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def validate_arithmetic_packet(packet, source_sha):
    generated = packet / "case/generated-tla"
    manifest = generated / "arithmetic-preparation.json"
    report = packet.parent / "result.json"
    required = {
        "authored-arithmetic-source.swift", "native-arithmetic-source.swift",
        "OrderedOverflow.tla", "OrderedOverflow.cfg", "SwiftTLANativeAssignmentActions.tla",
        "SwiftTLAArithmeticAssignmentSource.tla", "native-assignment-failure.json",
        "SwiftTLAOrderedRHSConfiguredProof.tla", "SwiftTLAOrderedRHSOutputProof.tla",
    }
    preparation = json.loads(report.read_text()) if report.is_file() and not report.is_symlink() else {}
    shared_variant = "GeneratedScalarConditionalSharedPrefixProofModel"
    shared_stem = f"SwiftTLAArithmeticAssignmentSource{shared_variant}"
    shared_proof = f"SwiftTLA{shared_variant}ConditionalOverflowHistory"
    shared_send = f"SwiftTLA{shared_variant}PublicSendBinding"
    shared_arms = [f"{shared_stem}Arm{arm}.tla" for arm in (1, 2)]
    shared_body = f"{shared_stem}Shared.tla"
    shared_domain = f"{shared_stem}Domain.tla"
    shared_members = f"{shared_variant}NativeMembers.swift"
    shared_compiled = "native-conditional-shared-prefix-source.swift"
    shared_files = {f"{shared_variant}.{ext}" for ext in ("swift", "tla", "cfg")}
    shared_files.update({f"{shared_proof}.tla", f"{shared_proof}ConfiguredProof.tla",
                         shared_members, shared_domain, shared_body, *shared_arms})
    shared = preparation.get("conditionalSharedPrefixHistory", {})
    shared_paths = {name: packet / "proof-inputs" / name for name in shared_files}
    has_shared = ("conditionalSharedPrefixHistory" in preparation
                  or "conditionalSharedPrefixPublicSendBinding" in preparation
                  or any(path.exists() or path.is_symlink() for path in
                         [*shared_paths.values(), packet / "proof-inputs" / f"{shared_send}.tla", packet / shared_compiled]))
    if ("arithmeticPreparation" not in preparation and not has_shared
            and not any(path.exists() or path.is_symlink() for path in
                        [manifest, *(generated / name for name in required)])):
        return
    if (preparation.get("status") != "FRESH_ACTUAL_PROOF_BYTES_MATCH_CHECKED_CANDIDATE"
            or preparation.get("sourceSHA") != source_sha
            or not manifest.is_file() or manifest.is_symlink()):
        raise ValueError("arithmetic packet requires matching fresh generation and preparation reports")
    arithmetic = json.loads(manifest.read_text())
    files = arithmetic.get("files", {})
    if (arithmetic != preparation.get("arithmeticPreparation")
            or arithmetic.get("sourceSHA") != source_sha or not required.issubset(files)
            or arithmetic.get("authoredSourceSHA256") != files["authored-arithmetic-source.swift"]
            or arithmetic.get("nativeSourceSHA256") != files["native-arithmetic-source.swift"]):
        raise ValueError("arithmetic packet manifest differs from fresh generation")
    for name, checksum in files.items():
        path = generated / name
        if (not re.fullmatch(r"[A-Za-z0-9_-]+[.](tla|cfg|json|swift)", name)
                or path.is_symlink() or not path.is_file() or checksum != digest(path)):
            raise ValueError(f"retained arithmetic packet mismatch: {name}")

    validate_send_packet(packet, preparation, "arithmeticPublicSendBinding",
                         "SwiftTLAArithmeticPublicSendBinding", arithmetic["nativeSourceSHA256"])
    copy = preparation.get("orderedCopyNativeOutput", {})
    conditional = preparation.get("conditionalOverflowHistory", {})
    conditional_members = "GeneratedScalarConditionalOverflowProofModelNativeMembers.swift"
    if has_shared:
        fixture = "Sources/UpstreamParity/ValidationModels/GeneratedScalarConditionalProofModel.swift"
        shared_hashes = shared.get("files", {})
        expected = {
            "sourceSHA": source_sha,
            "test": "GeneratedAtomicUpdateProofTests/sharedConditionalWriteSelectsOrStops",
            "fixture": fixture, "fixtureSHA256": preparation["inputs"][fixture],
            "authoredVariant": f"{shared_variant}.swift", "configuration": f"{shared_variant}.cfg",
            "proof": f"{shared_proof}.tla", "configuredProof": f"{shared_proof}ConfiguredProof.tla",
            "domainSource": shared_domain, "sharedSource": shared_body, "armSources": shared_arms,
        }
        if (any(shared.get(key) != value for key, value in expected.items())
                or shared_files != set(shared_hashes)
                or "conditionalSharedPrefixPublicSendBinding" not in preparation
                or any(path.is_symlink() or not path.is_file() or digest(path) != shared_hashes[name]
                       for name, path in shared_paths.items())):
            raise ValueError("retained shared-prefix conditional packet differs from fresh compiler evidence")
    for field, module, evidence, compiled_name, compiled_sha, attached_name, attached_sha in (
        ("orderedCopyPublicSendBinding", "SwiftTLAOrderedAssignmentCatalogOrderedCopySendBinding",
         copy, "native-ordered-copy-source.swift", copy.get("compiledSHA256"),
         "OrderedCopyNativeMembers.swift", copy.get("attachedSHA256")),
        ("conditionalPublicSendBinding", "SwiftTLAConditionalPublicSendBinding",
         conditional, "native-conditional-overflow-source.swift", conditional.get("compiledMembersSHA256"),
         conditional_members, conditional.get("files", {}).get(conditional_members)),
        ("conditionalSharedPrefixPublicSendBinding", shared_send,
         shared, shared_compiled, shared.get("compiledMembersSHA256"),
         shared_members, shared.get("files", {}).get(shared_members)),
    ):
        binding = packet / "proof-inputs" / (module + ".tla")
        if field in preparation or binding.exists() or binding.is_symlink():
            compiled = packet / compiled_name
            attached = packet / "proof-inputs" / attached_name
            if (evidence.get("matchingSourceAccurateTokens") is not True
                    or any(path.is_symlink() or not path.is_file() for path in (compiled, attached))
                    or digest(compiled) != compiled_sha or digest(attached) != attached_sha):
                raise ValueError(f"{field} source differs from the checked macro expansion")
            validate_send_packet(packet, preparation, field, module, compiled_sha)

    total_module = "SwiftTLAGeneratedScalarConditionalProofModelPublicSendBinding"
    total_binding = packet / "proof-inputs" / (total_module + ".tla")
    if "conditionalTotalPublicSendBinding" in preparation or total_binding.exists() or total_binding.is_symlink():
        compiled = generated / "native-conditional-source.swift"
        native_sha = preparation.get("conditionalPreparation", {}).get("nativeSourceSHA256")
        if compiled.is_symlink() or not compiled.is_file() or digest(compiled) != native_sha:
            raise ValueError("total conditional public send evidence differs from its retained compiler expansion")
        validate_send_packet(packet, preparation, "conditionalTotalPublicSendBinding", total_module, native_sha)


def validate_send_packet(packet, preparation, field, module_name, native_sha):
    send = preparation.get(field)
    module = packet / "proof-inputs" / (module_name + ".tla")
    if send is not None or module.exists() or module.is_symlink():
        operations = packet / "arithmetic-send/NativeMachineOperations.swift"
        checking = packet / "arithmetic-send/CheckingContext.swift"
        if any(path.is_symlink() or not path.is_file() for path in (module, operations, checking)):
            raise ValueError("retained public send evidence is incomplete")
        if (send != {"nativeSourceSHA256": native_sha,
                     "operationsSHA256": digest(operations), "checkingSHA256": digest(checking),
                     "moduleSHA256": digest(module)}
                or digest(operations) != preparation["inputs"]["Sources/SwiftTLA/NativeMachineOperations.swift"]
                or digest(checking) != preparation["inputs"]["Sources/SwiftTLA/CheckingContext.swift"]):
            raise ValueError("retained public send evidence differs from the compiler inputs or outputs")


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
    arguments = sys.argv[1:]
    thread_options = []
    if arguments[:1] == ["--paired-worker"]:
        arguments = arguments[1:]
        online_cpus = os.sysconf("SC_NPROCESSORS_ONLN")
        if online_cpus < 2:
            raise ValueError("paired proof checks require at least two online CPUs")
        thread_options = ["--threads", str(min(99, online_cpus // 2))]
    if not 3 <= len(arguments) <= 6:
        raise ValueError("expected packet, line range, optional candidate and helper/caller byte inputs")
    root = Path.cwd()
    packet = Path(arguments[0]).resolve(strict=True)
    first, last = map(int, arguments[1:3])
    original = packet / "case/generated-tla/SwiftTLAInitialFailureProof.tla"
    candidate = Path(arguments[3]).resolve(strict=True) if len(arguments) >= 4 else original
    byte_source = Path(arguments[4]).resolve(strict=True) if len(arguments) >= 5 else None
    caller_byte_source = Path(arguments[5]).resolve(strict=True) if len(arguments) == 6 else None
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
    if "configurationSHA256" in preparation or "nativeActionSHA256" in preparation:
        generated = packet / "case/generated-tla"
        bindings.update(configurationSHA256=generated / (preparation["module"] + ".cfg"),
                        nativeActionSHA256=generated / "SwiftTLANativeActions.tla")
    if "sequentialControlProofSHA256" in preparation:
        bindings["sequentialControlProofSHA256"] = packet / "case/generated-tla/SwiftTLASequentialControlProof.tla"
    for field, path in bindings.items():
        if digest(path) != preparation[field]:
            raise ValueError(f"retained packet mismatch: {field}")
    copy_modules = preparation.get("scalarCopyProofSHA256", {})
    if any(not re.fullmatch(r"[A-Za-z_][A-Za-z_0-9]*", module)
           or checksum != digest(packet / "case/generated-tla" / f"{module}.tla")
           for module, checksum in copy_modules.items()):
        raise ValueError("retained packet mismatch: scalarCopyProofSHA256")
    if (packet / "source-sha.txt").read_text().strip() != preparation["sourceSHA"]:
        raise ValueError("retained packet source revision mismatch")
    validate_arithmetic_packet(packet, preparation["sourceSHA"])
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
    command = [str(executable), *thread_options, "--strict", "--nofp", "--timing", "--toolbox", str(first), str(last),
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
