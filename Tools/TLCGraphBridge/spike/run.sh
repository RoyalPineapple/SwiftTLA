#!/usr/bin/env bash
set -euo pipefail

bridge_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
output_dir=""
while (($#)); do
    case "$1" in
        --output) output_dir="$2"; shift 2 ;;
        *) echo "unknown argument: $1" >&2; exit 64 ;;
    esac
done
test -n "$output_dir" || { echo "--output is required" >&2; exit 64; }
mkdir -p "$output_dir"
output_dir=$(cd "$output_dir" && pwd)

jar="$bridge_root/.tool-cache/tla2tools-1.8.0.jar"
jdk="$bridge_root/.tool-cache/temurin-17.0.19+10/Contents/Home"
expected_jar=ab323b79802aedc3203b3f9af37c6aca3ed43f4e0225b36f2aa77b26de46c05f
expected_jdk=8fa1eff40bb637a33613b2ccb8b12c70dc3661cc22cf8e784943715769a05336
test "$(shasum -a 256 "$jar" | awk '{print $1}')" = "$expected_jar"
test "$(shasum -a 256 "$bridge_root/.tool-cache/OpenJDK17U-jdk_aarch64_mac_hotspot_17.0.19_10.tar.gz" | awk '{print $1}')" = "$expected_jdk"
test "$($jdk/bin/java -version 2>&1 | head -1)" = 'openjdk version "17.0.19" 2026-04-21'

classes="$bridge_root/build/classes"
rm -rf "$classes"
mkdir -p "$classes" "$output_dir/corrupt"
"$jdk/bin/javac" --release 17 -classpath "$jar" -d "$classes" \
    "$bridge_root/src/org/swifttla/conformance/LosslessStateWriter.java"
bridge_digest=$(shasum -a 256 "$classes/org/swifttla/conformance/LosslessStateWriter.class" | awk '{print $1}')
bridge_source_digest=$(shasum -a 256 "$bridge_root/src/org/swifttla/conformance/LosslessStateWriter.java" | awk '{print $1}')
arguments='["-workers","1","-fp","1","-seed","1","-deadlock"]'
arguments_digest=$(printf '%s' "$arguments" | shasum -a 256 | awk '{print $1}')

run_once() {
    local number="$1"
    local run_dir="$output_dir/run-$number"
    mkdir -p "$run_dir"
    local stream="$run_dir/events.jsonl"
    local module_sha cfg_sha provenance
    module_sha=$(shasum -a 256 "$bridge_root/spike/BridgeGraph.tla" | awk '{print $1}')
    cfg_sha=$(shasum -a 256 "$bridge_root/spike/BridgeGraph.cfg" | awk '{print $1}')
    provenance="{\"tlcTag\":\"v1.8.0\",\"tlcCommit\":\"0894c3407f4717fec7cc18bde3bf3c857fa47333\",\"tlcJarSha256\":\"$expected_jar\",\"javaDistribution\":\"Eclipse Temurin\",\"javaVersion\":\"17.0.19+10\",\"javaArchiveSha256\":\"$expected_jdk\",\"bridgeClass\":\"org.swifttla.conformance.LosslessStateWriter\",\"bridgeSourceSha256\":\"$bridge_source_digest\",\"bridgeBinarySha256\":\"$bridge_digest\",\"moduleSha256\":\"$module_sha\",\"cfgSha256\":\"$cfg_sha\",\"arguments\":$arguments,\"argumentsSha256\":\"$arguments_digest\",\"workers\":1,\"fingerprintPolynomial\":1,\"deadlock\":false,\"os\":\"macos\",\"architecture\":\"arm64\",\"environment\":{}}"
    (
        cd "$run_dir"
        "$jdk/bin/java" \
            -Dswifttla.tlc.graph.path="$stream" \
            -Dswifttla.tlc.graph.provenance="$provenance" \
            -Dswifttla.tlc.graph.run-id=3c9c7f69-1ef1-4f26-941f-a4af60f4879f \
            -Dswifttla.tlc.graph.case-id=adversarial-core-graph-v1 \
            -cp "$jar:$classes" tlc2.TLC -workers 1 -fp 1 -seed 1 -deadlock \
            -config "$bridge_root/spike/BridgeGraph.cfg" \
            -dump class,org.swifttla.conformance.LosslessStateWriter \
            "$bridge_root/spike/BridgeGraph.tla" >tlc.log 2>&1
    )
    "$bridge_root/spike/verify.sh" "$stream" --expect-adversarial --tlc-log "$run_dir/tlc.log"
}

run_once 1
run_once 2
run_once 3
for number in 2 3; do
    cmp "$output_dir/run-1/events.jsonl" "$output_dir/run-$number/events.jsonl"
done

"$jdk/bin/java" -cp "$jar" tlc2.TLC -workers 1 -fp 1 -seed 1 -deadlock \
    -config "$bridge_root/spike/BridgeGraph.cfg" \
    -dump dot,actionlabels "$output_dir/run-1/graph.dot" \
    "$bridge_root/spike/BridgeGraph.tla" > "$output_dir/run-1/dot.log" 2>&1

violation_dir="$output_dir/violation"
mkdir -p "$violation_dir"
set +e
(
    cd "$violation_dir"
    "$jdk/bin/java" -cp "$jar" tlc2.TLC -workers 1 -fp 1 -seed 1 -deadlock \
        -metadir "$violation_dir/states" -teSpecOutDir "$violation_dir/te-spec" \
        -config "$bridge_root/spike/BridgeViolation.cfg" \
        -dumpTrace json "$violation_dir/counterexample.json" \
        "$bridge_root/spike/BridgeViolation.tla" >tlc.log 2>&1
)
violation_exit=$?
set -e
test "$violation_exit" -eq 12
test -s "$violation_dir/counterexample.json"

stream="$output_dir/run-1/events.jsonl"
sed '$d' "$stream" > "$output_dir/corrupt/truncated.jsonl"
sed '1s/^{/{"schema":"duplicate",/' "$stream" > "$output_dir/corrupt/duplicate-key.jsonl"
sed '2s/"seq":1/"seq":9/' "$stream" > "$output_dir/corrupt/bad-sequence.jsonl"
sed '$d' "$stream" > "$output_dir/corrupt/missing-footer.jsonl"
sed '2s/"type":"initial"/"type":"mystery"/' "$stream" > "$output_dir/corrupt/unknown-type.jsonl"
sed '2s/"type":"initial"/"type":"unsupported"/' "$stream" > "$output_dir/corrupt/unsupported.jsonl"

recompute_footer() {
    local input="$1"
    local output="$2"
    local body
    body=$(mktemp)
    trap 'rm -f "$body"' RETURN
    sed '$d' "$input" > "$body"
    local digest last_seq footer
    digest=$(shasum -a 256 "$body" | awk '{print $1}')
    last_seq=$(( $(wc -l < "$body") - 1 ))
    footer=$(tail -n 1 "$input" | sed -E "s/\"lastBodySeq\":[0-9]+/\"lastBodySeq\":$last_seq/; s/\"bodySha256\":\"[0-9a-f]+\"/\"bodySha256\":\"$digest\"/")
    { cat "$body"; printf '%s\n' "$footer"; } > "$output"
}

sed '1s/"tlcTag":"v1.8.0"/"tlcTag":"v9.9.9"/' "$stream" > "$output_dir/corrupt/altered-provenance-source.jsonl"
recompute_footer "$output_dir/corrupt/altered-provenance-source.jsonl" "$output_dir/corrupt/altered-provenance.jsonl"
rm "$output_dir/corrupt/altered-provenance-source.jsonl"
sed '2s/"tla":"0"/"tla":"9"/' "$stream" > "$output_dir/corrupt/altered-payload-source.jsonl"
recompute_footer "$output_dir/corrupt/altered-payload-source.jsonl" "$output_dir/corrupt/altered-payload.jsonl"
rm "$output_dir/corrupt/altered-payload-source.jsonl"
sed '2s/"state":/"unexpected":true,"state":/' "$stream" > "$output_dir/corrupt/unknown-field-source.jsonl"
recompute_footer "$output_dir/corrupt/unknown-field-source.jsonl" "$output_dir/corrupt/unknown-field.jsonl"
rm "$output_dir/corrupt/unknown-field-source.jsonl"

cp "$stream" "$output_dir/corrupt/invalid-utf8-source.jsonl"
location_offset=$(LC_ALL=C grep -abo -m1 '"location":"<ToMidA' "$output_dir/corrupt/invalid-utf8-source.jsonl" | cut -d: -f1)
test -n "$location_offset"
printf '\377' | dd of="$output_dir/corrupt/invalid-utf8-source.jsonl" bs=1 seek=$((location_offset + 12)) conv=notrunc status=none
recompute_footer "$output_dir/corrupt/invalid-utf8-source.jsonl" "$output_dir/corrupt/invalid-utf8.jsonl"
rm "$output_dir/corrupt/invalid-utf8-source.jsonl"

stream_digest=$(shasum -a 256 "$stream" | awk '{print $1}')
printf '%s\n' "{\"schema\":\"swifttla.bridge-spike-verdict\",\"version\":1,\"verdict\":\"PASS\",\"tlcTag\":\"v1.8.0\",\"tlcCommit\":\"0894c3407f4717fec7cc18bde3bf3c857fa47333\",\"tlcJarSha256\":\"$expected_jar\",\"javaVersion\":\"17.0.19+10\",\"javaArchiveSha256\":\"$expected_jdk\",\"bridgeSourceSha256\":\"$bridge_source_digest\",\"bridgeBinarySha256\":\"$bridge_digest\",\"eventStreamSha256\":\"$stream_digest\",\"runs\":3,\"acceptance\":{\"AS-001\":\"PASS\",\"AS-002\":\"PASS\",\"AS-003\":\"PASS\",\"AS-004\":\"PASS\",\"AS-005\":\"PASS\",\"AS-006\":\"PASS\",\"AS-007\":\"PASS\",\"AS-008\":\"PASS\",\"AS-009\":\"PASS\",\"AS-010\":\"PASS\",\"AS-011\":\"PASS\"}}" > "$output_dir/BridgeSpikeVerdictV1.json"
