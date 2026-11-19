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
import time


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def payloads(root):
    names = subprocess.check_output(["git", "ls-files", "-z"], cwd=root).decode().split("\0")[:-1]
    return {name: hashlib.sha256(os.readlink(root / name).encode() if (root / name).is_symlink()
                                else (root / name).read_bytes()).hexdigest() for name in names}


SIL_CERTIFICATE_SYMBOL = "$s8SwiftTLA27StraightLineAssignmentCheckO21orderedIntCertificate_5readsAC07OrderedhI0VSgAA9StateExprO_ShySSGtFZ"
SIL_EXPANSION_SYMBOL = "$s8SwiftTLA27StraightLineAssignmentCheckO25appendOrderedIntExpansion33_BE46BD14A2FCBC3229B8D4388070FB8DLL6origin4left5right2toySi_S2iSaySiAF_Sb8expandedtGztFZ"


def sil_tokens(line):
    """Retain every token; only whitespace and actual line comments are trivia."""
    tokens, offset = [], 0
    token = re.compile(r'"(?:\\.|[^"\\\r\n])*"|->|[^\s()\[\]{},:<>=/\"]+|[^\s"]')
    while offset < len(line):
        if line[offset].isspace():
            offset += 1
        elif line.startswith("//", offset):
            break
        else:
            match = token.match(line, offset)
            if not match:
                raise ValueError("unterminated SIL string literal")
            tokens.append(match[0])
            offset = match.end()
    return tokens


def sil_tla_token(token):
    # Pinned Zenon rejects UTF-8 string literals; retain those tokens as bytes.
    if not token.isascii():
        return "<<" + ", ".join(str(byte) for byte in token.encode("utf-8")) + ">>"
    if any(ord(character) < 32 or ord(character) == 127 for character in token):
        raise ValueError("control character in SIL token")
    return json.dumps(token)


def sil_scope_units(data, end):
    """Untrusted structural-parse proposal; every span needs a byte-bound proof."""
    if not 0 <= end <= len(data):
        raise ValueError("scope prefix is outside the compiler input")
    units, offset = [], 0
    while offset < end:
        start = offset
        if data.startswith(b"//", offset):
            newline = data.find(b"\n", offset, end)
            if newline < 0:
                raise ValueError("scope prefix ends inside a line comment")
            offset, kind = newline + 1, "comment"
        elif data[offset] == 34:
            offset += 1
            while offset < end and data[offset] not in (10, 13, 34, 92):
                offset += 1
            if offset == end or data[offset] != 34:
                raise ValueError("scope proposal does not support this quoted text")
            offset += 1
            if offset < len(data) and data[offset] == 34:
                raise ValueError("scope proposal does not support multiline strings")
            kind = "quoted"
        elif data[offset] in (123, 125):
            kind = "open" if data[offset] == 123 else "close"
            offset += 1
        elif data[offset] == 35:
            offset += 1
            if offset == len(data) or data[offset] in (34, 35):
                raise ValueError("scope proposal does not support raw strings")
            kind = "hash"
        else:
            while offset < end and data[offset] not in (34, 35, 47, 92, 123, 125):
                offset += 1
            if offset == start:
                raise ValueError("unsupported structural byte in scope proposal")
            kind = "plain"
        units.append({"start": start, "end": offset, "kind": kind})
    return units


def compiler_sil_function(data):
    """Propose full function tokens, without choosing or interpreting instructions."""
    lines = data.decode("utf-8").splitlines(keepends=True)
    starts = [i for i, line in enumerate(lines)
              if line.startswith("sil ") and "@" + SIL_CERTIFICATE_SYMBOL + " : " in line
              and sil_tokens(line)[-1:] == ["{"]]
    if len(starts) != 1:
        raise ValueError("expected one actual certificate-builder SIL definition")
    start = starts[0]
    ends = [i for i in range(start + 1, len(lines))
            if lines[i].strip() == "} // end sil function '" + SIL_CERTIFICATE_SYMBOL + "'"]
    if len(ends) != 1:
        raise ValueError("expected one complete certificate-builder SIL body")
    selected = lines[start:ends[0] + 1]
    records = []
    for i, line in enumerate(selected):
        tokens = sil_tokens(line)
        records.append({"line": start + i + 1, "raw": line, "tokens": tokens,
                        "tlaTokens": [sil_tla_token(token) for token in tokens]})
    return records


def sil_scope_proof(units, initial_stack, module_name, data):
    """Propose a proof; TLAPS must check every byte span and every composition."""
    if not re.fullmatch(r"[A-Za-z][A-Za-z0-9_]*", module_name) or not units:
        raise ValueError("invalid scope proof module or empty scope")
    lines = [f"---- MODULE {module_name} ----", "EXTENDS CompilerInputScopeRules", ""]
    selections, stack = {}, list(initial_stack)

    def emit(text):
        lines.extend(text.splitlines())

    def sequence(values):
        return "<<" + ", ".join(map(str, values)) + ">>"

    def byte_reads(positions):
        pages = sorted({position // 16 + 1 for position in positions})
        emit("        <2>reads. /\\ " + " /\\ ".join(
            f"CompilerInputByte[{position}] = CompilerInputPage{position // 16 + 1}[{position % 16 + 1}]"
            for position in positions))
        emit("            BY ONLY " + ", ".join(f"CompilerInputPage{page}AtFileOffsets" for page in pages) + ", SMT")
        return pages

    def interval(first, last, excluded):
        allowed = "0..255 \\ {" + ", ".join(map(str, excluded)) + "}"
        parts = []
        for page in range(first // 16 + 1, last // 16 + 2):
            base = (page - 1) * 16
            lo, hi = max(first, base), min(last, base + 15)
            if lo > hi:
                continue
            part = f"<2>p{page}"
            parts.append(part)
            emit(f'''        {part}. SILInputInterval({lo}, {hi}, {allowed})
            PROOF
            <3>values. \\A j \\in {lo - base + 1}..{hi - base + 1}: CompilerInputPage{page}[j] \\in {allowed}
                BY ONLY SMT DEF CompilerInputPage{page}
            <3>page. SILInputPageRange({base}, {lo}, {hi}, CompilerInputPage{page}, {allowed})
                BY ONLY <3>values, CompilerInputPage{page}AtFileOffsets, SMT DEF SILInputPageRange
            <3>. QED BY ONLY <3>page, LoadedPageSuppliesInputInterval, SMT''')
        emit(f"        <2>inside. \\A i \\in {first}..{last}: CompilerInputByte[i] \\in {allowed}")
        emit("            BY ONLY " + ", ".join(parts + ["SMT"]) + " DEF SILInputInterval")

    for index, unit in enumerate(units, 1):
        first, last, kind = unit["start"], unit["end"], unit["kind"]
        before = sequence(stack)
        if kind == "open":
            stack.append(first)
        elif kind == "close":
            if not stack:
                raise ValueError("unmatched closing brace in scope proposal")
            stack.pop()
        after = sequence(stack)
        name, start = f"{module_name}Unit{index}", len(lines) + 1
        emit(f'''THEOREM {name} ==
    SILScopeRange({first}, {last}, {before}, {after})
    PROOF
    <1>span. SILStructuralUnitAt({first}, {last}, "{kind}")
        PROOF''')
        if kind == "plain":
            interval(first, last - 1, [34, 35, 47, 92, 123, 125])
            facts, definitions = ["<2>inside"], ["SILPlainAt"]
        elif kind in ("comment", "quoted"):
            positions = [first, first + 1, last - 1] if kind == "comment" else [first, last - 1, last]
            edges = [f'CompilerInputByte[{i}] {"#" if kind == "quoted" and i == last else "="} '
                     f'{34 if kind == "quoted" else 10 if i == last - 1 else 47}' for i in positions]
            pages = byte_reads(positions)
            emit("        <2>edges. /\\ " + " /\\ ".join(edges))
            emit("            BY ONLY <2>reads, SMT DEF " + ", ".join(f"CompilerInputPage{p}" for p in pages))
            interval(first + (2 if kind == "comment" else 1), last - 2,
                     [10, 13] if kind == "comment" else [10, 13, 34, 92])
            facts = ["<2>edges", "<2>inside"]
            definitions = ["SILCommentAt" if kind == "comment" else "SILQuotedAt"]
        else:
            pages = byte_reads([first, last] if kind == "hash" else [first])
            edges = [f"CompilerInputByte[{first}] = " + str({"hash": 35, "open": 123, "close": 125}[kind])]
            if kind == "hash":
                edges.append(f"CompilerInputByte[{last}] = {data[last]}")
            emit("        <2>edges. /\\ " + " /\\ ".join(edges))
            emit("            BY ONLY <2>reads, SMT DEF " + ", ".join(f"CompilerInputPage{p}" for p in pages))
            facts, definitions = ["<2>edges"], []
        emit("        <2>. QED BY ONLY " + ", ".join(facts + ["SMT"])
             + " DEF " + ", ".join(["SILStructuralUnitAt", "CompilerInputSize"] + definitions))
        emit(f'''    <1>stack. /\\ SILScopeStackStep({first}, "{kind}", {before}, {after})
                /\\ {before} \\in Seq(Nat) /\\ {after} \\in Seq(Nat)
                /\\ {first} \\in Nat /\\ {last} \\in Nat
                /\\ "{kind}" \\in {{"plain", "comment", "quoted", "hash", "open", "close"}}
        BY ONLY SMT DEF SILScopeStackStep
    <1>. QED BY ONLY <1>span, <1>stack, CheckedStructuralUnitSuppliesScopeRange, SMT
''')
        selections[name] = {"lines": [start, len(lines)], "first": first, "last": last,
                            "before": before, "after": after}

    def compose(lo, hi):
        if lo == hi:
            return f"{module_name}Unit{lo}"
        middle = (lo + hi) // 2
        left, right = compose(lo, middle), compose(middle + 1, hi)
        a, b = selections[left], selections[right]
        if a["last"] != b["first"] or a["after"] != b["before"]:
            raise ValueError("noncontiguous scope proposal")
        name, start = f"{module_name}Units{lo}Through{hi}", len(lines) + 1
        emit(f'''THEOREM {name} ==
    SILScopeRange({a['first']}, {b['last']}, {a['before']}, {b['after']})
    BY ONLY {left}, {right}, CheckedScopeRangesCompose, SMT
''')
        selections[name] = {"lines": [start, len(lines)], "first": a["first"], "last": b["last"],
                            "before": a["before"], "after": b["after"]}
        return name

    final = compose(1, len(units))
    emit("=============================================================================")
    pages = {int(page) for page in re.findall(r"\bCompilerInputPage([0-9]+)(?:AtFileOffsets)?\b", "\n".join(lines))}
    blocks = sorted({(page - 1) // 64 + 1 for page in pages})
    # Export one scope result; keep intermediate obligations inside its proof.
    body = re.sub(r"(?<!<)<([0-9]+)>(?!>)", lambda match: f"<{int(match[1]) + 1}>", "\n".join(lines[3:-1]))
    body = re.sub(r"\b(" + "|".join(map(re.escape, selections)) + r")\b",
                  lambda match: "<1>" + match[1], body)
    body = re.sub(r"^THEOREM (<1>[A-Za-z0-9_]+) ==$", r"\1.", body, flags=re.M)
    body = re.sub(r"CompilerInputPage([0-9]+)AtFileOffsets",
                  lambda match: f"<1>InputPage{match[1]}", body)
    exported, result = module_name + "Scope", selections[final]
    header = [lines[0], lines[1] + "".join(f", CompilerInputPageBlock{block}" for block in blocks)]
    header += [f"LOCAL CompilerInputPage{page} == " + sequence(data[(page - 1) * 16:page * 16])
               for page in sorted(pages)]
    header += [
        "", f"THEOREM {exported} ==",
        f"    SILScopeRange({result['first']}, {result['last']}, {result['before']}, {result['after']})", "PROOF",
        "    <1> HIDE " + ", ".join(f"CompilerInputPageBlock{block}AtFileOffsets" for block in blocks)]
    for page in sorted(pages):
        base = (page - 1) * 16
        header += [f"    <1>InputPage{page}. \\A j \\in 1..{min(16, len(data) - base)}: "
                   f"CompilerInputByte[{base} + j - 1] = CompilerInputPage{page}[j]",
                   f"        BY ONLY CompilerInputPageBlock{(page - 1) // 64 + 1}AtFileOffsets, SMT DEF CompilerInputPage{page}"]
    offset = len(header) - 3
    for selection in selections.values():
        selection["lines"] = [line + offset for line in selection["lines"]]
    lines = header + ["    " + line for line in body.splitlines()] + [
        f"    <1>. QED BY <1>{final}", "============================================================================="]
    return "\n".join(lines) + "\n", {"status": "UNTRUSTED_PROOF_PROPOSAL", "final": exported,
        "steps": selections, "theorems": {exported: dict(result, lines=[header.index(f"THEOREM {exported} ==") + 1, len(lines) - 1])}}


def write_sil_scope_proofs(output, units, rules, data):
    """Keep concrete byte proofs small; the parent consumes their actual imported theorems."""
    parts_dir = output / "scope-parts"
    parts_dir.mkdir()
    parent = output / "CompilerExpansionSourceScope.tla"
    parent_imports = parent.with_suffix(".imports")
    parent_imports.mkdir()
    (parent_imports / rules.name).write_bytes(rules.read_bytes())
    stack, parts = [], []
    for start in range(0, len(units), 16):
        selected = units[start:start + 16]
        name = f"CompilerScopePart{len(parts) + 1:04d}"
        text, index = sil_scope_proof(selected, stack, name, data)
        path = parts_dir / (name + ".tla")
        path.write_text(text)
        imports = path.with_suffix(".imports")
        imports.mkdir()
        (imports / rules.name).write_bytes(rules.read_bytes())
        (parent_imports / path.name).write_bytes(path.read_bytes())
        for unit in selected:
            if unit["kind"] == "open":
                stack.append(unit["start"])
            elif unit["kind"] == "close":
                stack.pop()
        final = index["theorems"][index["final"]]
        index.update(candidate=str(path), candidateSHA256=digest(path), lineCount=len(text.splitlines()),
                     module=name, range=final, proofChecked=False)
        (parts_dir / (name + ".json")).write_text(json.dumps(index, indent=2) + "\n")
        parts.append(index)
    lines = ["---- MODULE CompilerExpansionSourceScope ----",
             "EXTENDS " + ", ".join(part["module"] for part in parts), ""]
    prior = None
    for i, part in enumerate(parts, 1):
        result = part["range"]
        name = f"ActualSourcePrefix{i}"
        facts = [part["final"]] if prior is None else [prior, part["final"], "CheckedScopeRangesCompose", "SMT"]
        lines += [f"THEOREM {name} ==",
                  f"    SILScopeRange({units[0]['start']}, {result['last']}, <<>>, {result['after']})",
                  "    BY ONLY " + ", ".join(facts), ""]
        prior = name
    lines += ["============================================================================="]
    parent.write_text("\n".join(lines) + "\n")
    manifest = {"status": "UNTRUSTED_PROOF_PROPOSALS", "candidate": str(parent),
                "candidateSHA256": digest(parent), "coreSHA256": digest(rules),
                "lineCount": len(lines), "final": prior, "parts": parts,
                "compilerAssumptionRemoved": False, "proofChecked": False}
    (output / "compiler-scope-proof-selections.json").write_text(json.dumps(manifest, indent=2) + "\n")
    return parent


def check_sil_tokens():
    assert sil_tokens('  cond_fail %1, "failure // payload" // comment\n') == [
        "cond_fail", "%1", ",", '"failure // payload"']
    assert sil_tokens('%2 = tuple (%3, %4)') == ["%2", "=", "tuple", "(", "%3", ",", "%4", ")"]
    assert sil_tokens('br bb14') != sil_tokens('br bb22')
    assert sil_tokens('br bb14//comment') == ["br", "bb14"]
    assert sil_tokens('(Int) -> Bool') == ["(", "Int", ")", "->", "Bool"]
    assert sil_tla_token("τ_0_0") == "<<207, 132, 95, 48, 95, 48>>"
    assert sil_tla_token("τ_0_0") != sil_tla_token("τ_0_1")
    assert sil_tla_token('"failure // payload"') == r'"\"failure // payload\""'
    try:
        sil_tokens('cond_fail %1, "unterminated')
    except ValueError:
        pass
    else:
        raise AssertionError("malformed string accepted")
    scope_source = b'sil @f : T {\n  "{quoted}" // } comment\n  ${ var T }\n}\n'
    units = sil_scope_units(scope_source, len(scope_source))
    assert units[0]["start"] == 0 and units[-1]["end"] == len(scope_source)
    assert all(a["end"] == b["start"] for a, b in zip(units, units[1:]))
    assert [u["kind"] for u in units if u["kind"] in ("open", "close")] == ["open", "open", "close", "close"]
    literal_scope = b"abcd{x}z"
    proof, _ = sil_scope_proof(sil_scope_units(literal_scope, len(literal_scope)), [], "ScopeLiteralContract", literal_scope)
    assert "SILScopeRange(4, 5, <<>>, <<4>>)" in proof, "proof nesting changed a source offset"
    assert "SILScopeRange(6, 7, <<4>>, <<>>)" in proof, "proof nesting changed the enclosing scope"
    for unsupported in [b'/* block */', b'"unterminated', b'"""raw"""', b'#"raw"#', b'"escaped\\n"']:
        try:
            sil_scope_units(unsupported, len(unsupported))
        except ValueError:
            pass
        else:
            raise AssertionError("unsupported scope text silently classified")


def capture_compiler_expansion(root, scratch, output, sil=False, named_function=None):
    """Retain resolved Swift declarations; this does not certify their interpretation."""
    source = root / "Sources/SwiftTLA/StraightLineAssignmentCheck.swift"
    expected = set((root / "Sources/SwiftTLA").rglob("*.swift"))
    sources = sorted(expected)
    if source not in sources:
        raise ValueError("certificate builder is missing from the actual module")
    inputs = {str(path.relative_to(root)): digest(path) for path in sources}
    compiler = Path(subprocess.check_output(["xcrun", "--find", "swift-frontend"], text=True).strip())
    sdk = subprocess.check_output(["xcrun", "--show-sdk-path"], text=True).strip()
    # Only the primary file's body is typechecked/dumped; other actual module
    # sources supply declarations. No copied facade or replacement declarations.
    # JSON dumps omit local declaration identities; text dumps retain their
    # declaration locations, needed to distinguish same-spelled local bindings.
    command = [str(compiler), "-frontend", "-emit-sil" if sil else "-dump-ast",
               "-primary-file", str(source)] + [str(p) for p in sources if p != source] + [
        "-parse-as-library", "-module-name", "SwiftTLA", "-package-name", "swifttla",
        "-swift-version", "5", "-target", "arm64-apple-macos14.0", "-sdk", sdk,
        "-DSWIFT_PACKAGE", "-DDEBUG", "-DSWIFT_MODULE_RESOURCE_BUNDLE_UNAVAILABLE", "-DXcode",
        "-warnings-as-errors", "-enable-experimental-feature", "StrictConcurrency",
        "-enable-experimental-feature", "DebugDescriptionMacro", "-enable-testing",
        "-module-cache-path", str(scratch / "compiler-module-cache")]
    if named_function:
        command += ["-Xllvm", f"-sil-print-function={named_function}",
                    "-Xllvm", "-sil-print-after=MandatoryInlining"]
    output.mkdir(parents=True)
    (output / "compiler-source.swift").write_bytes(source.read_bytes())
    receipt = {"scope": "COMPILER_REPRESENTATION_DIAGNOSTIC_NOT_PROOF", "command": command,
               "compilerSHA256": digest(compiler), "sourceInputs": inputs,
               "sourceRevision": subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip(),
               "sourceWorkingTree": subprocess.check_output(["git", "status", "--porcelain"], text=True),
               "interpretationProved": False, "compilerAssumptionRemoved": False}
    result = output / "capture.json"
    result.write_text(json.dumps(receipt, indent=2) + "\n")
    print(f"Typechecking actual certificate-builder source: {output}", flush=True)
    representation = output / ("compiler.sil" if sil else "compiler-ast.txt")
    with representation.open("wb") as ast, (output / "compiler.log").open("wb") as log:
        run = subprocess.run(command, stdout=ast, stderr=log)
    receipt["compilerExit"] = run.returncode
    receipt["inputsUnchanged"] = (expected == set((root / "Sources/SwiftTLA").rglob("*.swift"))
                                  and inputs == {str(p.relative_to(root)): digest(p) for p in sources})
    result.write_text(json.dumps(receipt, indent=2) + "\n")
    if run.returncode or not receipt["inputsUnchanged"]:
        raise ValueError("actual-source AST capture failed or its inputs changed")
    if named_function:
        # Debug printing is retained verbatim; no selected or normalized proof input.
        receipt["requestedFunction"] = named_function
        receipt["requestedPhase"] = "after MandatoryInlining"
        receipt["rawFunctionDumpSHA256"] = digest(output / "compiler.log")
        receipt["rawFunctionDumpBytes"] = (output / "compiler.log").stat().st_size
        receipt["silSHA256"] = digest(representation)
        receipt["selectionProved"] = False
        result.write_text(json.dumps(receipt, indent=2) + "\n")
        print("Named-function diagnostic retained verbatim; selection and interpretation remain unproved.", flush=True)
        return
    data = representation.read_bytes()
    if sil:
        if b"\0" in data or not data.startswith(b"sil_stage canonical\n"):
            raise ValueError("compiler did not emit canonical SIL")
        function = compiler_sil_function(data)
        (output / "compiler-function.json").write_text(json.dumps(function, indent=2) + "\n")
        prefix_end = sum(len(line) for line in data.splitlines(keepends=True)[:function[-1]["line"]])
        scope = {"scope": "UNTRUSTED_STRUCTURAL_PARSE_PROPOSAL", "prefixEnd": prefix_end,
                 "units": sil_scope_units(data, prefix_end), "selectionProved": False}
        (output / "compiler-scope-proposal.json").write_text(json.dumps(scope, indent=2) + "\n")
        rules = root / "Verification/Semantics/CompilerInputScopeRules.tla"
        proof = write_sil_scope_proofs(output, scope["units"], rules, data)
        receipt["scopeRulesSHA256"] = digest(rules)
        receipt["scopeProofSHA256"] = digest(proof)
        receipt["silFunctionSHA256"] = digest(output / "compiler-function.json")
        receipt["silSHA256"] = digest(representation)
        receipt["silBytes"] = len(data)
        result.write_text(json.dumps(receipt, indent=2) + "\n")
        print("Actual canonical SIL retained; its interpretation remains unproved.", flush=True)
        return
    if b"\0" in data or not data.startswith(b"(source_file ") or not data.rstrip().endswith(b")"):
        raise ValueError("compiler did not emit the expected source-file AST")
    receipt["astSHA256"] = digest(output / "compiler-ast.txt")
    receipt["astBytes"] = len(data)
    result.write_text(json.dumps(receipt, indent=2) + "\n")
    print("Actual typed AST retained; extraction and interpretation remain unproved.", flush=True)


def main():
    root = Path.cwd()
    scratch = Path(sys.argv[1]).resolve(strict=True)
    guarded_scratch = os.environ.get("SWIFTTLA_VALIDATION_SCRATCH_PATH")
    if not guarded_scratch or not scratch.samefile(guarded_scratch):
        raise ValueError("invoke through local-validation.sh proof-prepare")
    common = Path(subprocess.check_output(["git", "rev-parse", "--git-common-dir"], text=True).strip()).resolve()
    output = Path(sys.argv[3]).resolve()
    if not output.is_relative_to(common / "swifttla-proof-evidence") or output.exists():
        raise ValueError("output must be a new proof-evidence directory")
    if sys.argv[4] in ["compiler-expansion", "compiler-expansion-sil", "compiler-expansion-function", "compiler-expansion-helper"]:
        capture_compiler_expansion(root, scratch, output,
                                   sil=sys.argv[4] != "compiler-expansion",
                                   named_function={"compiler-expansion-function": SIL_CERTIFICATE_SYMBOL,
                                                   "compiler-expansion-helper": SIL_EXPANSION_SYMBOL}.get(sys.argv[4]))
        return
    build = Path(sys.argv[2]).resolve(strict=True)
    expected = Path(sys.argv[4]).resolve(strict=True)
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
        spec = importlib.util.spec_from_file_location("native_source", root / "scripts/retain-native-initial-source.py")
        native_source = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(native_source)
        products = (build / "debug").resolve(strict=True)
        plugin = products / "SwiftTLAPlugin"
        if not plugin.is_file() or not (products / "SwiftTLA.swiftmodule").exists():
            raise ValueError("verified compiler cache is unavailable; no consumer rebuild started")
        compiler_temporary = scratch / "native-compiler"
        compiler_temporary.mkdir()
        compiler_env = dict(os.environ, TMPDIR=str(compiler_temporary) + "/")
        started = time.time_ns()
        command = ["xcrun", "swiftc", "-c", "-g", "-parse-as-library", "-swift-version", "5",
                   "-target", "arm64-apple-macos14.0", "-warnings-as-errors",
                   "-enable-experimental-feature", "StrictConcurrency",
                   "-package-name", "SwiftTLA", "-module-name", "UpstreamParity", "-I", str(products),
                   "-load-plugin-executable", str(plugin) + "#SwiftTLAPlugin",
                   "-Xfrontend", "-emit-macro-expansion-files", "-Xfrontend", "debug",
                   "-o", str(compiler_temporary / "pilot.o"), str(root / native_source.MODEL)]
        receipt["nativeCompilerCommand"] = command
        receipt["macroPluginSHA256"] = digest(plugin)
        with (output / "native-compiler.log").open("wb") as log:
            run = subprocess.run(command, env=compiler_env, stdout=log, stderr=subprocess.STDOUT)
        receipt["nativeCompilerExit"] = run.returncode
        if run.returncode:
            raise ValueError("focused pilot compiler capture failed; no consumer rebuild started")
        expansions = [p for p in (compiler_temporary / "swift-generated-sources").glob(native_source.EXPANSION)
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
        print("Fresh existing-pilot compiler output retained; running focused consumer.", flush=True)
        command = ["swift", "test", "-Xswiftc", "-warnings-as-errors",
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
    if sys.argv[1:] == ["--self-check"]:
        check_sil_tokens()
        print("Compiler SIL token retention controls passed (no interpretation proof credit).")
    else:
        main()
