"""Exercise the pinned TLC configuration parser during hosted tool setup."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile

java, tlc_jar, bridge_jar = (str(Path(argument).resolve()) for argument in sys.argv[1:])

with tempfile.TemporaryDirectory() as temporary:
    root = Path(temporary)
    module = root / "Fixture.tla"
    module.write_text(r"""---- MODULE Fixture ----
EXTENDS Integers
VARIABLE x
Safe == x >= 0
WrappedSafe == Safe
NestedSafe == WrappedSafe
Live == <>Safe
WrappedLive == Live
Different == x < 0
Spec == x = 0 /\ [][x' = x]_x
====
""", encoding="utf-8")

    def parse(source, name, source_module=module):
        configuration = root / f"{name}.cfg"
        output = root / f"{name}.json"
        configuration.write_text(source, encoding="utf-8")
        result = subprocess.run(
            [java, "-cp", f"{bridge_jar}:{tlc_jar}",
             "org.swifttla.conformance.ConfigurationParser", str(source_module), str(configuration), str(output),
             "Safe", "TypeOK", "Live", "EventuallyDone", "Other",
             "TypeInvariant", "Invariant", "Termination", "NoSolutions"],
            capture_output=True, text=True, timeout=30, cwd=source_module.parent,
        )
        return result, output

    source = '''\\* Keywords in comments and strings are not directives.
CONSTANT Label = "INVARIANT PROPERTY CHECK_DEADLOCK"
CONSTANT Limit = 3
INIT Start
NEXT Advance
CONSTRAINT WithinBounds
ACTION_CONSTRAINT AllowedStep
VIEW Projection
SYMMETRY Permutations
INVARIANTS Safe TypeOK
PROPERTIES Live EventuallyDone
CHECK_DEADLOCK FALSE
'''
    result, output = parse(source, "original")
    assert result.returncode == 0, result.stderr + result.stdout
    parsed = json.loads(output.read_text(encoding="utf-8"))
    assert parsed["invariants"] == ["Safe", "TypeOK"], parsed
    assert parsed["properties"] == ["Live", "EventuallyDone"], parsed
    assert parsed["checksDeadlock"] is False, parsed
    declarations = parsed["declarations"]
    for directive in ("INIT Start", "NEXT Advance", "CONSTRAINT WithinBounds",
                      "ACTION_CONSTRAINT AllowedStep", "VIEW Projection"):
        assert directive in declarations.splitlines(), parsed
    assert '"INVARIANT PROPERTY CHECK_DEADLOCK"' in declarations, parsed
    assert not any(line.startswith(("INVARIANT", "PROPERTY", "SYMMETRY", "CHECK_DEADLOCK"))
                   for line in declarations.splitlines()), parsed

    # Selecting different checks must leave the parsed model definition intact.
    result, output = parse(declarations + "INVARIANT Other\nCHECK_DEADLOCK TRUE\n", "selected")
    assert result.returncode == 0, result.stderr + result.stdout
    selected = json.loads(output.read_text(encoding="utf-8"))
    assert selected["declarations"] == declarations, selected
    assert selected["invariants"] == ["Other"], selected
    assert selected["properties"] == [], selected
    assert selected["checksDeadlock"] is True, selected

    # ModelConfig can otherwise swallow a lexer error and accept a valid prefix.
    result, output = parse('SPECIFICATION Spec\nCONSTANT Label = "unterminated', "malformed")
    assert result.returncode != 0, "Malformed configuration was accepted"
    assert not output.exists(), "Malformed configuration produced a usable result"

    result, output = parse("SPECIFICATION Spec\nINVARIANT NestedSafe\nPROPERTY WrappedLive\n", "aliases")
    assert result.returncode == 0, result.stderr + result.stdout
    aliases = json.loads(output.read_text(encoding="utf-8"))
    assert aliases["invariants"] == ["Safe"], aliases
    assert aliases["properties"] == ["Live"], aliases

    # A configured replacement can change an alias's meaning. Never bypass it.
    result, output = parse("CONSTANT WrappedSafe <- Different\nSPECIFICATION Spec\nINVARIANT WrappedSafe\n", "overridden")
    assert result.returncode == 0, result.stderr + result.stdout
    overridden = json.loads(output.read_text(encoding="utf-8"))
    assert overridden["invariants"] == ["WrappedSafe"], overridden

    result, output = parse("SPECIFICATION Spec\nINVARIANT Different\n", "distinct-property")
    assert result.returncode == 0, result.stderr + result.stdout
    distinct = json.loads(output.read_text(encoding="utf-8"))
    assert distinct["invariants"] == ["Different"], distinct

    original = Path(__file__).resolve().parents[2] / "Verification/FiniteGraph/fixtures/n-queens-four"
    result, output = parse((original / "MC.cfg").read_text(encoding="utf-8"), "upstream-queens", original / "MC.tla")
    assert result.returncode == 0, result.stderr + result.stdout
    queens = json.loads(output.read_text(encoding="utf-8"))
    assert queens["invariants"] == ["TypeInvariant", "Invariant", "NoSolutions"], queens
    assert queens["properties"] == ["Termination"], queens
    assert queens["checksDeadlock"] is True, queens
