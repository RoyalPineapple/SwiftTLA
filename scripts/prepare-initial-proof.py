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


def branchwise_state_proofs(model, checking_inputs, original_rules):
    """Specialize only the retained branchwise proof inputs. Keep the actual module intact."""
    model_name = b"BranchwiseConjunctionFailureOrderModel"
    data_name = b"SwiftTLABranchwiseCheckingInputs"
    projected_model = b"BranchwiseFailureStateProjection"
    projected_data = b"SwiftTLABranchwiseProjectedCheckingInputs"
    histories_name = b"BranchwiseConjunctionFailureHistories"
    variables = b"divisor, modulus, selected, result"

    def replace_once(contents, old, new):
        if contents.count(old) != 1:
            raise ValueError(f"unexpected branchwise proof input boundary: {old!r}")
        return contents.replace(old, new, 1)

    physical = model.splitlines()
    if (physical[:2] != [b"---- MODULE " + model_name + b" ----", b"EXTENDS Integers, FiniteSets, Sequences"]
            or physical.count(b"VARIABLES " + variables) != 1 or physical.count(b"Init ==") != 1):
        raise ValueError("unexpected branchwise physical module header")
    init = physical.index(b"Init ==")
    state_lines = [line for line in physical[2:init] if line and not line.startswith(
        (b"VARIABLES ", b"pick == "))]
    operators = []
    for line in state_lines:
        name, separator, expression = line.partition(b" == ")
        if (not separator or not re.fullmatch(rb"[A-Za-z_][A-Za-z0-9_]*", name)
                or re.search(rb"'|\b(?:ENABLED|UNCHANGED)\b", expression)):
            raise ValueError("branchwise projection would include a non-state definition")
        operators.append(name)
    if (len(operators) != len(set(operators)) or not {
            b"vars", b"__SwiftTLAActionFailureHistory0", b"__SwiftTLAAnyEvaluationFailure0",
            b"__SwiftTLAEvaluationOK", b"SelectionFloor", b"ResultNonnegative", b"DivisorNonnegative",
    }.issubset(operators)):
        raise ValueError("incomplete or duplicate branchwise physical state operators")
    projection = b"\n".join([
        b"---- MODULE " + projected_model + b" ----", physical[1], b"CONSTANTS " + variables,
        b"", *state_lines, b"====", b"",
    ])

    definitions = b"BranchwiseStateProjectionMatchesEmission"
    bindings = b", ".join(name + b" <- " + name for name in variables.split(b", "))
    bridge = [
        b"---- MODULE BranchwiseFailureStateProjectionProof ----",
        b"EXTENDS TLAPS, " + model_name, b"",
        b"LOCAL Projected == INSTANCE " + projected_model, b"    WITH " + bindings, b"",
        definitions + b" ==",
    ]
    equalities = [b"Projected!" + name + b" = " + name for name in operators]
    bridge.extend(b"    /\\ " + equality for equality in equalities)
    bridge.extend([b"", b"THEOREM TheProjectionUsesTheActualEmittedStateOperators == " + definitions, b"PROOF"])
    for index, (name, equality, line) in enumerate(zip(operators, equalities, state_lines), 1):
        bridge.append(f"<1>{index}. ".encode() + equality)
        refs = [f"<1>{previous}".encode() for previous, dependency in enumerate(operators[:index - 1], 1)
                if re.search(rb"(?<![A-Za-z0-9_])" + dependency + rb"(?![A-Za-z0-9_])",
                             line.partition(b" == ")[2])]
        uses = b", ".join(refs) + b" " if refs else b""
        bridge.append(b"    BY ONLY " + uses + b"DEF Projected!" + name + b", " + name)
    steps = b", ".join(f"<1>{i}".encode() for i in range(1, len(operators) + 1))
    bridge.extend([b"<1>. QED BY ONLY " + steps + b" DEF " + definitions, b"====", b""])

    def without_range(contents, start, stop):
        if contents.count(start) != 1 or contents.count(stop) != 1:
            raise ValueError("branchwise source proof split changed")
        before, middle = contents.split(start)
        _, after = middle.split(stop)
        return before + stop + after

    histories = replace_once(original_rules, b"MODULE BranchwiseConjunctionFailureOrderProof ",
                             b"MODULE " + histories_name + b" ")
    histories = replace_once(histories, b"EXTENDS TLAPS, " + model_name, b"EXTENDS TLAPS, " + projected_model)
    histories = without_range(histories, b"\nSourceInit ==\n", b"\nSourceFirstDivisionFailure ==")
    histories = without_range(histories, b"UngatedLaterModuloFailure ==", b"\nTHEOREM EmittedFirstFailureMatchesSource")
    histories = without_range(histories, b"\nSourceLabeledStep(label) ==",
                              b"SourceOrderedFailureHistory ==")
    histories = replace_once(histories, b"DEF FailureHistory!ActionAlternativeFailureHistory\n"
                             b"SourceOrderedFailureHistory ==",
                             b"DEF FailureHistory!ActionAlternativeFailureHistory\n\nSourceOrderedFailureHistory ==")
    for name in (b"FailureHistory", b"FailureEvent", b"DivisionEvent", b"NegativeModuloEvent",
                 b"LeftBefore", b"RightBefore"):
        histories = replace_once(histories, b"\nLOCAL " + name, b"\n" + name)
    histories = replace_once(histories, b"\n" + b"=" * 77 + b"\n", b"\n" + b"=" * 150 + b"\n")

    checking = replace_once(checking_inputs, b"MODULE " + data_name + b" ", b"MODULE " + projected_data + b" ")
    checking = replace_once(checking, b"BranchwisePredicates(snapshot) == INSTANCE " + model_name + b" WITH ",
                            b"BranchwisePredicates(snapshot) == INSTANCE " + projected_model + b" WITH ")
    return {
        projected_model.decode() + ".tla": projection,
        "BranchwiseFailureStateProjectionProof.tla": b"\n".join(bridge),
        histories_name.decode() + ".tla": histories,
        projected_data.decode() + ".tla": checking,
    }


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
    selection = sys.argv[5:]
    if selection and (selection != ["ordered-copy-actions"] or sys.argv[4].startswith("compiler-expansion")):
        raise ValueError("ordered-copy-actions requires a checked proof input")
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
        pilot_compiler_command = command
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
        test_filter = "InitialFailureEvidenceTests"
        ordered_copy_attachments = scratch / "ordered-copy-attachments" if selection else None
        if ordered_copy_attachments is not None:
            ordered_copy_attachments.mkdir()
            test_filter += "|OrderedStepTests/orderedActionsSupplySelectedProofs"
        command = ["swift", "test", "-Xswiftc", "-warnings-as-errors",
                   "--disable-automatic-resolution", "--filter", test_filter, "-j", "1",
                   "--scratch-path", str(build)]
        if ordered_copy_attachments is not None:
            command += ["--attachments-path", str(ordered_copy_attachments)]
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
        authored = root / native_source.MODEL
        command = [str(binary), "initial-failure", "prepare", "--authored-source", str(authored),
                   "--native-source", str(retained), "--output", str(packet / "case")]
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
        action_source = packet / "case/generated-tla/SwiftTLAStayActionSource.tla"
        if (preparation["authoredSourceSHA256"] != inputs[native_source.MODEL]
                or preparation["authoredSourceSHA256"] != digest(packet / "case/authored-model.swift")
                or preparation["actionSourceSHA256"] != digest(action_source)):
            raise ValueError("authored model or action source binding differs")
        generated = proof.parent
        if (preparation["configurationSHA256"] != digest(generated / (preparation["module"] + ".cfg"))
                or preparation["nativeActionSHA256"] != digest(generated / "SwiftTLANativeActions.tla")
                or preparation["sequentialControlProofSHA256"] != digest(generated / "SwiftTLASequentialControlProof.tla")):
            raise ValueError("normal configuration, native action, or sequential control binding differs")
        copy_modules = preparation.get("scalarCopyProofSHA256", {})
        if copy_modules and (len(copy_modules) not in (2, 3)
                or any(not re.fullmatch(r"[A-Za-z_][A-Za-z_0-9]*", module)
                       or checksum != digest(generated / f"{module}.tla")
                       for module, checksum in copy_modules.items())):
            raise ValueError("generic scalar copy source or parent binding differs")
        if proof.read_bytes() != expected_bytes or preparation["proofSHA256"] != digest(proof):
            raise ValueError("actual compiler did not emit the checked proof bytes exactly")
        def capture_model_expansion(model, task, include_extension=False, owner=None, compiler_module="UpstreamParity"):
            owner = owner or Path(model).stem
            module_stem = f"{len(compiler_module)}{compiler_module}"
            started = time.time_ns()
            command = pilot_compiler_command[:-2] + [
                str(compiler_temporary / (task + ".o")), str(root / model)]
            command[command.index("-module-name") + 1] = compiler_module
            if include_extension:
                # Debug expansion files can omit an empty conformance extension.
                command = command[:2] + ["-Xfrontend", "-dump-macro-expansions"] + command[2:]
            receipt[task + "CompilerCommand"] = command
            log_file = output / (task + "-compiler.log")
            with log_file.open("wb") as log:
                subprocess.run(command, env=compiler_env, stdout=log, stderr=subprocess.STDOUT, check=True)
            folder = compiler_temporary / "swift-generated-sources"
            dumps = {}
            prefix = f"@__swiftmacro_{module_stem}*{owner}*TLAModel"
            if compiler_module == "SwiftTLATests":
                prefix = f"@__swiftmacro_{module_stem}*{len(owner)}{owner}*TLAModel"
            roles = {"members": list(folder.glob(prefix + "fMm_.swift"))}
            if include_extension:
                extension = rb"\s*extension " + re.escape(owner.encode("ascii")) + rb"\s*:"
                files = [path for path in folder.glob(prefix + "*.swift")
                         if not path.is_symlink() and re.match(extension, path.read_bytes())]
                if files:
                    roles["extension"] = files
                else:
                    # Bind the extension to its exact symbol in this invocation's dump.
                    name = f"@__swiftmacro_{module_stem}{len(owner)}{owner}8TLAModelfMe_.swift"
                    delimit = rb"^-{8,}\n"
                    blocks = re.findall(rb"^" + re.escape(name.encode()) + rb"\n" + delimit
                                        + rb"(.*?)" + delimit, log_file.read_bytes(), re.MULTILINE | re.DOTALL)
                    if len(blocks) != 1 or not re.match(extension, blocks[0]):
                        raise ValueError(f"expected one compiler-dumped conformance for {name}")
                    dumps["extension"] = (blocks[0], name)
            for part, expansions in roles.items():
                if len(expansions) != 1 or expansions[0].is_symlink():
                    raise ValueError(f"expected exactly one fresh {owner} {part} expansion")
                expansion = expansions[0]
                before = expansion.stat()
                captured = expansion.read_bytes()
                after = expansion.stat()
                if (before.st_mtime_ns < started or len(captured) != before.st_size
                        or (before.st_ino, before.st_size, before.st_mtime_ns)
                        != (after.st_ino, after.st_size, after.st_mtime_ns)):
                    raise ValueError(f"{owner} {part} expansion is stale or changed during capture")
                origin = native_source.source_range(captured, root, model)
                dumps[part] = (captured, origin)
            return dumps

        def capture_action(model, task, proof_template=None):
            captured, origin = capture_model_expansion(model, task)["members"]
            receipt[task + "SourceOrigin"] = origin
            retained = output / ("native-" + task + "-source.swift")
            retained.write_bytes(captured)
            args = [str(binary), "initial-failure", "prepare-" + task, "--authored-source",
                    str(root / model), "--native-source", str(retained)]
            if proof_template is not None:
                args.extend(["--proof", str(root / proof_template)])
            with (output / (task + "-prepare.log")).open("wb") as log:
                subprocess.run(args + ["--output", str(generated)], env=env, stdout=log,
                               stderr=subprocess.STDOUT, check=True)
            return retained

        conditional_model = "Sources/UpstreamParity/ValidationModels/GeneratedScalarConditionalProofModel.swift"
        conditional_template = "Verification/Semantics/GeneratedScalarConditionalProof.tla"
        conditional_retained = capture_action(conditional_model, "conditional", conditional_template)
        conditional_report = json.loads((proof.parent / "conditional-preparation.json").read_text())
        conditional_files = {
            "authoredSourceSHA256": proof.parent / "authored-conditional-source.swift",
            "nativeSourceSHA256": proof.parent / "native-conditional-source.swift",
            "modelSHA256": proof.parent / "GeneratedScalarConditionalProofModel.tla",
            "proofSHA256": proof.parent / "GeneratedScalarConditionalNative.tla",
        }
        if (conditional_report["sourceSHA"] != head
                or conditional_report["authoredSourceSHA256"] != inputs[conditional_model]
                or conditional_report["nativeSourceSHA256"] != digest(conditional_retained)
                or conditional_report["proofTemplateSHA256"] != inputs[conditional_template]
                or any(conditional_report[key] != digest(path) for key, path in conditional_files.items())):
            raise ValueError("actual native conditional evidence binding differs")
        receipt["conditionalPreparation"] = conditional_report
        arithmetic_model = "Sources/UpstreamParity/ValidationModels/OrderedOverflowModel.swift"
        retained = capture_action(arithmetic_model, "arithmetic")
        arithmetic = json.loads((generated / "arithmetic-preparation.json").read_text())
        files = arithmetic["files"]
        required = {"authored-arithmetic-source.swift", "native-arithmetic-source.swift",
                    "OrderedOverflow.tla", "OrderedOverflow.cfg", "SwiftTLANativeAssignmentActions.tla",
                    "SwiftTLAArithmeticAssignmentSource.tla", "native-assignment-failure.json",
                    "SwiftTLAOrderedRHSConfiguredProof.tla", "SwiftTLAOrderedRHSOutputProof.tla"}
        if (arithmetic["sourceSHA"] != head or not required.issubset(files)
                or arithmetic["authoredSourceSHA256"] != inputs[arithmetic_model]
                or arithmetic["nativeSourceSHA256"] != digest(retained)
                or files["authored-arithmetic-source.swift"] != inputs[arithmetic_model]
                or files["native-arithmetic-source.swift"] != digest(retained)
                or any(not re.fullmatch(r"[A-Za-z0-9_-]+[.](tla|cfg|json|swift)", name)
                       or (generated / name).is_symlink()
                       or checksum != digest(generated / name) for name, checksum in files.items())):
            raise ValueError("arithmetic action evidence differs from the fresh compiler inputs or outputs")
        receipt["arithmeticPreparation"] = arithmetic
        stack_seed = "Sources/UpstreamParity/CompilerPasses/OrderedIntTraversalPass.swift"
        installed_seed = "Sources/SwiftTLA/Generated/OrderedIntTraversalPass.swift"
        caller_source = "Sources/SwiftTLA/StraightLineAssignmentCheck.swift"
        caller_bytes = (root / caller_source).read_bytes()
        installed = installed_seed in inputs
        caller_uses_seed = b"OrderedIntTraversalPass._machineForRefinement(" in caller_bytes
        if installed != caller_uses_seed or (installed and stack_seed not in inputs):
            raise ValueError("production stack pass requires both authored source and its installed Swift expansion")
        stack_files = {}
        if stack_seed in inputs:
            stack_plugin_sha = digest(plugin)
            dumps = capture_model_expansion(stack_seed, "compiler-stack-seed", include_extension=True)
            stack = packet / "compiler-stack-seed"
            stack.mkdir()
            bodies = {}
            for part, (captured, origin) in dumps.items():
                suffix = origin.encode("utf-8") + b"\n"
                if part == "extension" and origin.startswith("@__swiftmacro_"):
                    bodies[part] = captured
                else:
                    if not captured.endswith(suffix):
                        raise ValueError("unexpected stack pass origin footer")
                    bodies[part] = captured[:-len(suffix)]
                (stack / f"{part}.swift").write_bytes(captured)
            if not re.fullmatch(rb"\s*extension OrderedIntTraversalPass: SwiftTLA\.StateMachine\s*\{\s*\}\s*",
                                bodies["extension"]):
                raise ValueError("expected the generated unconfigured state-machine extension")
            generated = (b"// Generated from OrderedIntTraversalPass.swift by the SwiftTLA macro.\n"
                         b"package struct OrderedIntTraversalPass: Sendable {\n"
                         + bodies["members"] + b"}\n" + bodies["extension"])
            candidate = stack / "OrderedIntTraversalPass.swift"
            candidate.write_bytes(generated)
            if installed and ((root / installed_seed).is_symlink() or (root / installed_seed).read_bytes() != generated):
                raise ValueError("installed stack pass differs from the fresh macro output")
            authored = stack / "authored-model.swift"
            shutil.copyfile(root / stack_seed, authored)
            caller = stack / "compiler-caller.swift"
            caller.write_bytes(caller_bytes)
            if digest(authored) != inputs[stack_seed] or digest(caller) != inputs[caller_source]:
                raise ValueError("stack pass source or compiler caller changed while being retained")
            render = stack / "rendered"
            stack_command = [str(binary), "native", "prepare-compiler-stack-seed",
                             "--authored-source", str(authored), "--native-source", str(stack / "members.swift"), "--output", str(render)]
            with (output / "compiler-stack-seed-render.log").open("wb") as log:
                subprocess.run(stack_command, env=env, stdout=log, stderr=subprocess.STDOUT, check=True)
            capture_source = (stack / "members.swift").read_bytes()
            correct_capture = (b"SwiftTLA._appendNativeOutcome(&result, Snapshot(state: State(pending: "
                               b"_value_pending_0, leftChild: _value_leftChild_1, rightChild: _value_rightChild_2)))")
            if capture_source.count(correct_capture) != 1:
                raise ValueError("expected one physical stack initializer snapshot append")
            wrong_capture = correct_capture.replace(b"leftChild: _value_leftChild_1", b"leftChild: _value_rightChild_2")
            wrong_native = stack / "members-wrong-initial-capture.swift"
            wrong_native.write_bytes(capture_source.replace(correct_capture, wrong_capture, 1))
            wrong_output = stack / "wrong-initial-capture-render"
            wrong_command = [str(binary), "native", "prepare-compiler-stack-seed",
                             "--authored-source", str(authored), "--native-source", str(wrong_native),
                             "--output", str(wrong_output)]
            wrong_log = stack / "wrong-initial-capture.log"
            with wrong_log.open("wb") as log:
                wrong_result = subprocess.run(wrong_command, env=env, stdout=log, stderr=subprocess.STDOUT, check=False)
            wrong_path = "native.traversal.initial.assembly"
            if wrong_result.returncode != 2 or wrong_output.exists() or wrong_path.encode() not in wrong_log.read_bytes():
                raise ValueError("the guarded stack evidence checker did not reject the wrong initializer binding")
            render_receipt = json.loads((render / "files.json").read_text())
            stack_files = render_receipt.get("files", {})
            if (not re.fullmatch(r"[a-f0-9]{64}", render_receipt.get("compilationIdentity", ""))
                    or set(stack_files) != {"OrderedIntTraversalPass.tla", "OrderedIntTraversalPass.cfg",
                                            "OrderedIntTraversalPassSource.tla"}
                    or any((render / name).is_symlink() or digest(render / name) != value
                           for name, value in stack_files.items())):
                raise ValueError("actual stack pass render differs from its receipt")
            if digest(plugin) != stack_plugin_sha:
                raise ValueError("macro plugin changed while retaining the stack pass")
            receipt["compilerStackSeed"] = {
                "sourceSHA": head, "macroPluginSHA256": stack_plugin_sha,
                "validatorSHA256": capture["binarySHA256"],
                "stage": "INSTALLED_REGENERATED" if installed else "BOOTSTRAP_CANDIDATE",
                "installedBytesMatch": installed, "rendering": render_receipt,
                "wrongInitialCaptureControl": {
                    "originalSHA256": digest(stack / "members.swift"),
                    "mutatedSHA256": digest(wrong_native), "logSHA256": digest(wrong_log),
                    "diagnosticPath": wrong_path, "exitCode": wrong_result.returncode,
                },
                "mathematicalProof": False, "hostedAdmission": False,
                "artifacts": {str(path.relative_to(stack)): digest(path) for path in stack.rglob("*") if path.is_file()},
                "sourceOrigins": {part: origin for part, (_, origin) in dumps.items()},
            }

        imports = packet / "proof-inputs"
        imports.mkdir()
        names = ["OrderedIntExpressionRule", "IndexedHistoryRules", "InitializationOutcomeRules",
                 "InitializationComposition", "OrderedIntInitializationComposition", "FiniteSetMembershipRule", "OrderedScalarCopyRule", "DirectCopyParserRule", "DirectCopyLexicalRule",
                 "ScalarCopyOutputBinding", "OrderedIntAssignmentListRule",
                 "CertifiedReadAssignmentObservation", "PhysicalIntAssignmentRhsRule", "NativeIntAssignmentListRule",
                 "RenderedIntAssignmentTerms", "RenderedIntAssignmentActionRule", "OrderedAssignmentOutputRules",
                 "ActionOutcomeInterface", "FrameActionRule", "PendingWriteOutcomeRule", "NativePendingWriteFold", "NativeScalarCopyRule", "ConditionalOutcomeRules", "NormalSeedCFG"]
        names += ["CompilerOutput/SeedAndArithmeticConfiguredBehavior", "CompilerOutput/SeedConfiguredBehavior",
                  "CompilerOutput/SwiftTLACopyCertifiedAssignmentObservation",
                  "CompilerOutput/SwiftTLAOrderedRHSBackendAgreement", "CompilerOutput/OrderedOverflowInitialDisabled",
                  "CompilerOutput/OrderedOverflowDirectInitialDisabled"]
        names += ["CheckingSelectionRule", "CheckingSelectionComposition", "CheckingSelectionCompilerBinding",
                  "ActionFailureHistoryProjection"]
        branchwise_rules = ["BranchwiseConjunctionFailureOrderProof", "ActionTreeOutcomeComposition",
                            "ConditionalActionRule", "AlternativeActionRule", "BranchwiseConjunctionRule",
                            "GuardActionRule", "AlternativeTraversalRule"]
        names += branchwise_rules
        if stack_files:
            names += ["SequencePrefixRule", "CompilerOutput/OrderedIntTraversalPassProof", "OrderedIntTraversalNativeRule",
                      "GeneratedCertificateExpansionRule", "CompilerOutput/OrderedIntTraversalPassConfiguredProof"]
        branchwise_imports = {name + ".tla" for name in branchwise_rules}
        branchwise_imports.update({"BranchwiseConjunctionFailureOrderModel.tla", "SwiftTLABranchwiseCheckingInputs.tla",
                                   "IndexedHistoryRules.tla", "ActionOutcomeInterface.tla", "ActionFailureHistoryProjection.tla",
                                   "CheckingSelectionRule.tla", "CheckingSelectionComposition.tla",
                                   "CheckingSelectionCompilerBinding.tla"})
        proof_hashes = []
        branchwise_hashes = {}
        for name in names:
            source = f"Verification/Semantics/{name}.tla"
            retained_input = imports / Path(source).name
            shutil.copyfile(root / source, retained_input)
            sha = digest(retained_input)
            if sha != inputs[source]:
                raise ValueError(f"retained proof input differs from the captured source: {source}")
            proof_hashes.append(f"{sha}  {retained_input.relative_to(packet)}\n")
            if retained_input.name in branchwise_imports:
                branchwise_hashes[retained_input.name] = sha
        if ordered_copy_attachments is not None:
            swift_source = "Tests/SwiftTLATests/OrderedStepFixtures.swift"
            native_attachment = "OrderedCopyNativeMembers.swift"
            attached_source = Path(swift_source).name
            catalog_module = "SwiftTLAOrderedAssignmentCatalogOrderedCopy"
            attached = {path.name: path for path in ordered_copy_attachments.iterdir()}
            ordinals = sorted(int(match[1]) for name in attached if
                              (match := re.fullmatch(r"SwiftTLAArithmeticAssignmentSourceOrderedCopyAction([1-9][0-9]*)\.tla", name)))
            expected = {"OrderedCopy.tla", f"{catalog_module}.tla", f"{catalog_module}NativeData.tla",
                        attached_source, native_attachment}
            expected.update(f"SwiftTLA{kind}OrderedCopyAction{row}.tla"
                            for kind in ("ArithmeticAssignmentSource", "OrderedRHSOutputProof") for row in ordinals)
            native_row_modules = [f"{catalog_module}NativeAction{row}" for row in ordinals]
            expected.update(f"{module}.tla" for module in native_row_modules)
            if (ordinals != [1, 2] or set(attached) != expected
                    or any(path.is_symlink() or not path.is_file() for path in attached.values())
                    or digest(attached[attached_source]) != inputs[swift_source]):
                raise ValueError("selected OrderedCopy test did not attach its authored source and complete catalog proofs")
            catalog_extends = "EXTENDS " + ", ".join(native_row_modules)
            row_extends = f"EXTENDS {catalog_module}NativeData"
            if (any(attached[f"{module}.tla"].read_text().splitlines()[1:2] != [row_extends]
                    for module in native_row_modules)
                    or attached[f"{catalog_module}.tla"].read_text().splitlines()[1:2] != [catalog_extends]):
                raise ValueError("retained OrderedCopy catalog does not consume every attached native row module")
            plugin_before = digest(plugin)
            compiled, origin = capture_model_expansion(swift_source, "ordered-copy",
                owner="OrderedCopyModel", compiler_module="SwiftTLATests")["members"]
            modeled_source = (root / swift_source).read_text().splitlines()
            owner_lines = [line for line, text in enumerate(modeled_source, 1) if text == "struct OrderedCopyModel {"]
            if len(owner_lines) != 1:
                raise ValueError("expected one OrderedCopyModel declaration in the existing fixture")
            owner_end = next(line for line in range(owner_lines[0] + 1, len(modeled_source) + 1)
                             if modeled_source[line - 1] == "}")
            location = origin.removeprefix(f"// original-source-range: {root / swift_source}:")
            if location != f"{owner_end}:1-{owner_end}:1" or digest(plugin) != plugin_before:
                raise ValueError("OrderedCopy members were emitted for a different Swift declaration or plug-in")
            retained_ordered_copy = packet / "native-ordered-copy-source.swift"
            retained_ordered_copy.write_bytes(compiled)
            token_check = [str(binary), "native", "verify-member-tokens",
                           "--compiled-members", str(retained_ordered_copy),
                           "--attached-members", str(attached[native_attachment])]
            with (output / "ordered-copy-compare-members.log").open("wb") as log:
                subprocess.run(token_check, env=env, stdout=log, stderr=subprocess.STDOUT, check=True)
            receipt["orderedCopyNativeOutput"] = {
                "compiledSHA256": digest(retained_ordered_copy),
                "attachedSHA256": digest(attached[native_attachment]),
                "matchingSourceAccurateTokens": True,
                "sourceOrigin": origin,
                "compilerModule": "SwiftTLATests",
                "macroPluginSHA256": plugin_before,
                "validatorSHA256": digest(binary),
            }
            proof_files = {}
            for name, path in sorted(attached.items()):
                retained_input = imports / name
                data = path.read_bytes()
                if name.endswith(".tla") and data.split(b"\n", 1)[0] != f"---- MODULE {path.stem} ----".encode():
                    raise ValueError(f"unexpected attached module header: {name}")
                with retained_input.open("xb") as retained_file:
                    retained_file.write(data)
                sha = digest(retained_input)
                proof_hashes.append(f"{sha}  {retained_input.relative_to(packet)}\n")
                proof_files[name] = sha
            receipt["orderedCopyActionProofs"] = {
                "sourceSHA": head, "authoredSource": swift_source,
                "test": "OrderedStepTests/orderedActionsSupplySelectedProofs",
                "files": proof_files,
            }
        if stack_files:
            for name in ["OrderedIntTraversalPass.tla", "OrderedIntTraversalPassSource.tla"]:
                retained_input = imports / name
                shutil.copyfile(render / name, retained_input)
                sha = digest(retained_input)
                if sha != stack_files[name]:
                    raise ValueError(f"retained stack pass module differs from its emitted output: {name}")
                proof_hashes.append(f"{sha}  {retained_input.relative_to(packet)}\n")
        (packet / "proof-inputs.sha256").write_text("".join(proof_hashes))
        tool_inputs = packet / "toolchain/build-inputs"
        tool_inputs.mkdir(parents=True)
        for name, directory in [("proof-toolchain.json", "Verification/Semantics"), ("packaging.patch", "Tools/TLAPS")]:
            shutil.copyfile(root / directory / name, tool_inputs / name)
        (packet / "source-sha.txt").write_text(head + "\n")
        shutil.copyfile(output / "local-native-source.json", packet / "local-native-source.json")
        if payloads(root) != inputs or subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip() != head:
            raise ValueError("source inputs changed during the guarded compiler check")
        if stack_files:
            stack_proof_inputs = {
                "OrderedIntTraversalPass.tla", "OrderedIntTraversalPassSource.tla", "SequencePrefixRule.tla",
                "OrderedIntTraversalPassProof.tla",
                "OrderedIntTraversalNativeRule.tla", "GeneratedCertificateExpansionRule.tla",
                "OrderedIntTraversalPassConfiguredProof.tla", "OrderedIntExpressionRule.tla", "IndexedHistoryRules.tla",
            }
            parent = "Verification/Semantics/CompilerOutput/CompilerExpansionUsesGeneratedPass.tla"
            seed_receipt = receipt["compilerStackSeed"]
            seed_receipt["proofInputs"] = {name: digest(imports / name) for name in sorted(stack_proof_inputs)}
            seed_receipt["parentSourceSHA256"] = inputs[parent]
            seed_receipt["sourceInputsSHA256"] = digest(output / "inputs.json")
            (stack / "capture.json").write_text(json.dumps(seed_receipt, indent=2) + "\n")

        selection_runs = [
            ("checking-selection", "prepare-selection", "CheckSelectionModels.swift",
             "SelectedChecks", "SwiftTLAActualCheckingSelection", "checkingSelectionPreparation", False),
            ("checking-selection-branchwise", "prepare-branchwise-selection", "BranchwiseConjunctionFailureOrderModel.swift",
             "BranchwiseConjunctionFailureOrderModel", "SwiftTLABranchwiseCheckingInputs",
             "branchwiseCheckingSelectionPreparation", True),
        ]
        for folder, native_command, model_source, module, proof_module, receipt_key, nonempty in selection_runs:
            selection_model = "Sources/UpstreamParity/ValidationModels/" + model_source
            selection = packet / folder
            command = [str(binary), "native", native_command, "--authored-source",
                       str(root / selection_model), "--output", str(selection)]
            with (output / f"{folder}-prepare.log").open("wb") as log:
                subprocess.run(command, env=env, stdout=log, stderr=subprocess.STDOUT, check=True)
            selection_files = json.loads((selection / "files.json").read_text())
            expected = {"authored-model.swift", f"{module}.tla", f"{module}.cfg",
                        f"{proof_module}.tla", f"{module}.native.bin", f"{module}.native.profile.json"}
            if (set(selection_files) != expected
                    or selection_files["authored-model.swift"] != inputs[selection_model]
                    or any(path.is_symlink() or checksum != digest(path)
                           for key, checksum in selection_files.items() for path in [selection / key])):
                raise ValueError(f"{folder} evidence differs from the captured source or outputs")
            profile = json.loads((selection / f"{module}.native.profile.json").read_text())
            history = profile.get("orderedActionFailureHistory")
            if profile.get("caseID") != "Selected" or not isinstance(history, list) or (nonempty and not history):
                raise ValueError(f"{folder} packet lacks its required observed ordered native history")
            receipt[receipt_key] = selection_files
        branchwise = packet / "checking-selection-branchwise"
        combined_name = "SwiftTLABranchwiseSelectedChecking.tla"
        template = f"Verification/Semantics/CompilerOutput/{combined_name}"
        template_bytes = (root / template).read_bytes()
        template_sha = hashlib.sha256(template_bytes).hexdigest()
        marker = b"\\* BranchwisePhysicalPageRequests"
        page_request = re.escape(rb"\* ") + rb"CallerInputPage[1-9][0-9]*"
        page_request += rb"(?: (?:CallerInput|CompilerInput)Page[1-9][0-9]*)*"
        requests = [line for line in (branchwise / "SwiftTLABranchwiseCheckingInputs.tla").read_bytes().splitlines()
                    if re.fullmatch(page_request, line)]
        if (template_sha != inputs[template] or template_bytes.count(marker) != 1
                or marker not in template_bytes.splitlines() or len(requests) != 1):
            raise ValueError("branchwise proof template or physical byte-page requests differ")
        combined = branchwise / combined_name
        combined.write_bytes(template_bytes.replace(marker, requests[0], 1))
        witness_source = "Verification/Semantics/BranchwiseConjunctionFailureOrderSwiftWitness.txt"
        witness = branchwise / Path(witness_source).name
        shutil.copyfile(root / witness_source, witness)
        witness_sha = digest(witness)
        if witness_sha != inputs[witness_source]:
            raise ValueError("retained branchwise Swift witness differs from the committed input")
        branchwise_files = receipt["branchwiseCheckingSelectionPreparation"]

        for branchwise_input in ["BranchwiseConjunctionFailureOrderModel.tla", "SwiftTLABranchwiseCheckingInputs.tla"]:
            retained_input = imports / branchwise_input
            shutil.copyfile(packet / "checking-selection-branchwise" / branchwise_input, retained_input)
            sha = digest(retained_input)
            if sha != branchwise_files[branchwise_input]:
                raise ValueError(f"retained branchwise input differs from the actual configured output: {branchwise_input}")
            proof_hashes.append(f"{sha}  {retained_input.relative_to(packet)}\n")
            branchwise_hashes[branchwise_input] = sha
        actual_module = imports / "BranchwiseConjunctionFailureOrderModel.tla"
        actual_inputs = imports / "SwiftTLABranchwiseCheckingInputs.tla"
        original_m8 = imports / "BranchwiseConjunctionFailureOrderProof.tla"
        projected = branchwise_state_proofs(actual_module.read_bytes(), actual_inputs.read_bytes(),
                                           original_m8.read_bytes())
        for name, data in projected.items():
            retained = imports / name
            with retained.open("xb") as retained_file:
                retained_file.write(data)
            sha = digest(retained)
            proof_hashes.append(f"{sha}  {retained.relative_to(packet)}\n")
            branchwise_hashes[name] = sha
        branchwise_imports.update(projected)
        if branchwise_hashes.keys() != branchwise_imports:
            raise ValueError("incomplete branchwise proof inputs")
        receipt["branchwiseCombinedProof"] = {
            "template": template, "templateSHA256": template_sha,
            "proof": str(combined.relative_to(packet)),
            "files": branchwise_files | {combined.name: digest(combined), witness.name: witness_sha},
            "proofInputs": branchwise_hashes,
        }
        (packet / "proof-inputs.sha256").write_text("".join(proof_hashes))
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
