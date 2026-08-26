#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)
bridge_root="$repo_root/Tools/TLCGraphBridge"
output_dir=$(mktemp -d)
trap 'rm -rf "$output_dir"' EXIT

"$bridge_root/spike/run.sh" --output "$output_dir"

stream="$output_dir/run-1/events.jsonl"
test -s "$stream"
grep -F '"type":"initial"' "$stream" | test "$(wc -l | tr -d ' ')" -eq 2
grep -F '"name":"ToMidA"' "$stream" >/dev/null
grep -F '"name":"ToMidB"' "$stream" >/dev/null
grep -F '"name":"SelfLoop"' "$stream" >/dev/null
grep -F '"seen":true' "$stream" >/dev/null
grep -F '"type":"footer"' "$stream" >/dev/null
for binding in integer boolean text set tuple record function; do
    grep -F "\"name\":\"$binding\"" "$stream" >/dev/null
done
test -s "$output_dir/run-1/graph.dot"
test -s "$output_dir/violation/counterexample.json"

for non_graph in "$output_dir/run-1/graph.dot" "$output_dir/violation/counterexample.json"; do
    if "$bridge_root/spike/verify.sh" "$non_graph"; then
        echo "non-graph input was accepted: $non_graph" >&2
        exit 1
    fi
done

for name in truncated duplicate-key bad-sequence missing-footer unknown-type unsupported altered-provenance altered-payload unknown-field; do
    test -s "$output_dir/corrupt/$name.jsonl"
    if "$bridge_root/spike/verify.sh" "$output_dir/corrupt/$name.jsonl"; then
        echo "corrupt stream was accepted: $name" >&2
        exit 1
    fi
done

invalid_utf8="$output_dir/corrupt/invalid-utf8.jsonl"
test -s "$invalid_utf8"
body="$output_dir/invalid-utf8-body"
sed '$d' "$invalid_utf8" > "$body"
expected_digest=$(shasum -a 256 "$body" | awk '{print $1}')
actual_digest=$(tail -n 1 "$invalid_utf8" | sed -nE 's/.*"bodySha256":"([0-9a-f]+)".*/\1/p')
test "$expected_digest" = "$actual_digest"
LC_ALL=C grep -q $'\377' "$invalid_utf8"

set +e
diagnostic=$("$bridge_root/spike/verify.sh" "$invalid_utf8" 2>&1)
exit_status=$?
set -e
test "$exit_status" -eq 2
case "$diagnostic" in
    *"invalid UTF-8 event stream"*) ;;
    *)
        echo "invalid UTF-8 diagnostic was not encoding-specific: $diagnostic" >&2
        exit 1
        ;;
esac
