#!/usr/bin/env bash
set -euo pipefail

# Hosted diagnostic only. Never bypass the local validation wrapper with this script.
[[ "${GITHUB_ACTIONS:-}" == true ]] || { echo 'This comparison runs only in GitHub Actions.' >&2; exit 64; }
[[ $# == 3 ]] || { echo 'usage: profile-native-machines.sh BASELINE CANDIDATE OUTPUT' >&2; exit 64; }
baseline_root="$1"
candidate_root="$2"
output_root="$3"
mkdir -p "$output_root"
fixture="$candidate_root/Tests/SwiftTLATests/NativeMachinePerformanceTests.swift"
[[ -f "$fixture" ]] || { echo 'Candidate performance test fixture is missing.' >&2; exit 1; }
cp "$fixture" "$output_root/NativeMachinePerformanceTests.swift"
xcrun swift --version > "$output_root/toolchain.txt"
sw_vers >> "$output_root/toolchain.txt"
uname -m >> "$output_root/toolchain.txt"
shasum -a 256 "$fixture" > "$output_root/fixture-sha256.txt"
cat > "$output_root/measurement-scope.txt" <<'SCOPE'
Both revisions build the same focused release SwiftPM harness and test source.
Build time includes macro-expansion dump instrumentation; dependency resolution is excluded.
Binary size is the focused test executable, not an application or the complete repository test suite.
Generated-source bytes sum captured macro expansion bodies; per-expansion names and byte counts are retained.
ContinuousClock measurements follow warmup, with equal semantic checksums and no timing thresholds.
Construction retains every result through the allocation snapshot; outer retention buffers are preallocated. Non-inlined consumers exercise retained state/control after timing.
Malloc snapshots measure process-wide retained live blocks/bytes in the default zone, not total allocations or peaks.
Optional Instruments traces launch the Swift Testing helper that loads the test bundle, not swift test. Raw traces and export tables require attribution review before reporting allocation totals.
Both release builds enable testing access for the formal-engine comparison. This can affect optimization and test bundle size; results describe this identical diagnostic harness.
These measurements are hosted diagnostics, not a replacement for CI correctness admission.
SCOPE

for revision in baseline candidate; do
    if [[ "$revision" == baseline ]]; then source_root="$baseline_root"; else source_root="$candidate_root"; fi
    destination="$output_root/$revision"
    harness="$RUNNER_TEMP/native-machine-performance-$revision"
    mkdir -p "$destination" "$harness/Sources" "$harness/Tests/SwiftTLATests"
    git -C "$source_root" rev-parse HEAD > "$destination/revision.txt"
    for target in SwiftTLA SwiftTLAMacros SwiftTLAPlugin; do
        cp -R "$source_root/Sources/$target" "$harness/Sources/$target"
    done
    cp "$fixture" "$harness/Tests/SwiftTLATests/NativeMachinePerformanceTests.swift"
    if [[ -f "$candidate_root/Package.resolved" ]]; then cp "$candidate_root/Package.resolved" "$harness/Package.resolved"; fi
    cat > "$harness/Package.swift" <<'MANIFEST'
// swift-tools-version: 5.9
import PackageDescription
import CompilerPluginSupport
let settings: [SwiftSetting] = [.enableExperimentalFeature("StrictConcurrency")]
let package = Package(
    name: "SwiftTLA",
    platforms: [.macOS(.v14)],
    dependencies: [.package(url: "https://github.com/swiftlang/swift-syntax", from: "600.0.0")],
    targets: [
        .target(name: "SwiftTLA", dependencies: [
            .product(name: "SwiftParser", package: "swift-syntax"),
            .product(name: "SwiftBasicFormat", package: "swift-syntax"),
            .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
            .product(name: "SwiftSyntax", package: "swift-syntax"),
            .product(name: "SwiftSyntaxMacros", package: "swift-syntax")
        ], swiftSettings: settings),
        .target(name: "SwiftTLAMacros", dependencies: ["SwiftTLA", "SwiftTLAPlugin"], swiftSettings: settings),
        .macro(name: "SwiftTLAPlugin", dependencies: [
            "SwiftTLA",
            .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
            .product(name: "SwiftSyntax", package: "swift-syntax"),
            .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
            .product(name: "SwiftDiagnostics", package: "swift-syntax"),
            .product(name: "SwiftParser", package: "swift-syntax")
        ], swiftSettings: settings),
        .testTarget(name: "SwiftTLATests", dependencies: ["SwiftTLA", "SwiftTLAMacros"], swiftSettings: settings)
    ]
)
MANIFEST
    (
        cd "$harness"
        swift package resolve > "$destination/resolve.log" 2>&1
        cp Package.resolved "$destination/Package.resolved"
        /usr/bin/time -p swift build -c release --build-tests -j 1 \
            -Xswiftc -enable-testing -Xswiftc -Xfrontend -Xswiftc -dump-macro-expansions \
            > "$destination/build.stdout.log" 2> "$destination/build.stderr.log"
        swift test -c release --skip-build --no-parallel --filter NativeMachinePerformanceTests \
            > "$destination/measurements.log" 2>&1
        swift build -c release --show-bin-path > "$destination/bin-path.txt"
    )
    binary_dir="$(cat "$destination/bin-path.txt")"
    test_image="$binary_dir/SwiftTLAPackageTests.xctest/Contents/MacOS/SwiftTLAPackageTests"
    [[ -f "$test_image" ]] || { echo "Missing test bundle image: $test_image" >&2; exit 1; }
    stat -f '%z' "$test_image" > "$destination/test-bundle-bytes.txt"
    size "$test_image" > "$destination/test-bundle-sections.txt"
    python3 - "$destination" <<'PY'
import json, pathlib, re, sys
root = pathlib.Path(sys.argv[1])
text = (root / 'build.stdout.log').read_text() + '\n' + (root / 'build.stderr.log').read_text()
expansions = re.findall(r'(?m)^(@__swiftmacro[^\n]*)\n-{10,}\n(.*?)\n-{10,}(?:\n|$)', text, re.S)
unique_expansions = dict.fromkeys(expansions)
entries = [{'name': name, 'utf8Bytes': len(body.encode('utf-8'))} for name, body in unique_expansions]
(root / 'macro-expansions.json').write_text(json.dumps({'expansions': entries, 'totalUTF8Bytes': sum(e['utf8Bytes'] for e in entries) if entries else None, 'status': 'captured' if entries else 'unavailable: dump format not recognized'}, indent=2))
times = re.findall(r'(?m)^(real|user|sys)\s+(\d+(?:\.\d+)?)$', text)
(root / 'build-time.json').write_text(json.dumps(dict(times), indent=2))
PY
    if [[ "${RECORD_ALLOCATIONS:-false}" == true ]]; then
        # Failure to profile (permissions/template availability) must not masquerade
        # as zero allocations or erase ordinary release timing evidence.
        # Darwin test products are bundles. Launch the same in-process loader
        # SwiftPM uses, so Instruments observes the tests rather than the build tool.
        swift_tool="$(xcrun --find swift)"
        test_runner="$(dirname "$swift_tool")/../libexec/swift/pm/swiftpm-testing-helper"
        [[ -x "$test_runner" ]] || { echo "Missing Swift Testing runner: $test_runner" >&2; exit 1; }
        if xcrun xctrace record --template Allocations --time-limit 30s \
            --output "$destination/allocations.trace" --launch -- "$test_runner" \
            --test-bundle-path "$test_image" \
            --testing-library swift-testing --filter NativeMachinePerformanceTests \
            > "$destination/allocations-record.log" 2>&1; then
            xcrun xctrace export --input "$destination/allocations.trace" --toc \
                --output "$destination/allocations-toc.xml" \
                > "$destination/allocations-export.log" 2>&1 || true
            python3 - "$destination" <<'PY'
import json, pathlib, subprocess, sys, xml.etree.ElementTree as ET
root = pathlib.Path(sys.argv[1])
toc = root / 'allocations-toc.xml'
results = []
try:
    document = ET.parse(toc).getroot()
    for run_index, run in enumerate(document.findall('run'), start=1):
        for table_index, table in enumerate(run.findall('./data/table'), start=1):
            schema = table.get('schema', '')
            if 'alloc' not in schema.lower():
                continue
            output = f'allocations-run-{run_index}-table-{table_index}.xml'
            # Positional selectors avoid interpreting schema names as XPath syntax.
            xpath = f'/trace-toc/run[{run_index}]/data/table[{table_index}]'
            command = ['xcrun', 'xctrace', 'export', '--input', str(root / 'allocations.trace'),
                       '--xpath', xpath, '--output', str(root / output)]
            result = subprocess.run(command, capture_output=True, text=True)
            results.append({'schema': schema, 'file': output, 'exitCode': result.returncode,
                            'diagnostic': result.stdout + result.stderr})
    status = 'exported' if results and all(r['exitCode'] == 0 for r in results) else 'unavailable or incomplete'
except (OSError, ET.ParseError) as error:
    status = f'unavailable: {error}'
(root / 'allocations-tables.json').write_text(json.dumps({'status': status, 'tables': results}, indent=2))
PY
        else
            echo 'Allocation recording unavailable; inspect allocations-record.log. No allocation totals reported.' > "$destination/allocations-status.txt"
        fi
    fi
done
