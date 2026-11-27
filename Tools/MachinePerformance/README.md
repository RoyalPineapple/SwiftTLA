# Generated machine performance

This macOS suite measures what an application pays to construct a generated machine, send an action, read its current state, keep old states and explicitly request a formal projection. The executable imports the generated models from a separate Swift module. It uses the production macro, emitter and runtime. The three synthetic models isolate operations. ConfiguredCounter, BoundedFIFO, CoffeeCan and NanoBlockchain come directly from the checkout being measured.

## Reproduce

Use a checkout and a repository-approved local-validation wrapper that supports the four-job release port builder. Set DEVELOPER_DIR to the Xcode installation used for that run. The experiment's build receipt identifies the checkout, toolchain, inputs and executable. The temporary package lives in the checkout’s ignored .context directory. Its internal executable product name allows the existing build wrapper to build it.

```sh
python3 build.py "$OUT/probe" --repo "$CHECKOUT" --wrapper "$WRAPPER" --heap-probe
python3 build.py "$OUT/release" --repo "$CHECKOUT" --wrapper "$WRAPPER"
"$OUT/release/machine-performance" layout > "$OUT/layout.json"
python3 run.py "$OUT/release/machine-performance" "$OUT/timing"
python3 allocations.py "$OUT/release/machine-performance" "$OUT/probe/libHeapProbe.dylib" "$OUT/allocations.json"
```

Use a new output directory for a new experiment. Run timing serially on a quiet host. The client accepts a single case, size, iterations per batch and number of batches. For example, `machine-performance inventory.touch 16384 100 5` repeatedly changes one dictionary entry and observes both sides of the transition. An independent stack sample during this case identifies where the time goes. Keep stack samples and allocator instrumentation separate from timing.

## Read the outputs

- The layout command reports inline size, stride and alignment for concrete generated State, Action and Snapshot types. Heap buffers referenced by these values are measured separately.
- Each row in samples.jsonl is a separate process. The driver calibrates iterations, then executes three seeded, shuffled rounds. Each process records five timed batches and separate individual timings. The main estimate is the median of the three process medians. The summary includes their range, individual p95, individual sample count, and peak process RSS. The per-operation timer has measurable overhead on cheap calls. The clock case measures an increment through the same driver. Fresh-process first calls exclude executable startup. The process wall time includes launch and teardown. OS disk caches stay warm.
- A cycle is one benchmark operation. FIFO sends four actions. Counter sends exactly the configured number. Hash and projection are explicit requests against a snapshot. For actorBurst the throughput loop crosses into actor isolation once per batch. Its individual samples still measure a single awaited send. The actor case runs from the command-line main actor with one outstanding request.
- Hand controls are optimized Swift. hand.sameStorage starts from the generated initial state's dictionary and returns both before and after. helper.touch calls the runtime's public generic helper from the same client. hand.checkedTouch preserves the presence check and uses a concrete [Int: Int] helper. Both consume the previous and updated values. hand.inPlace models exclusive ownership and returns only the updated value. inventory.discard uses the ordinary generated send without retaining the previous state. The fixed-length append cases branch from a retained prefilled initial state for each operation. keep32 retains a rolling history of 32 previous states.
- Allocation runs count successful calls through the Darwin malloc-family entry points listed in HeapProbe.c. Each process requires a one-allocation, 257-byte positive control. The clock case must count zero. Requested bytes include replacement buffers. They measure allocation traffic. RSS measures the process high-water mark including setup. Neither number quantifies bytes still live after an operation. Direct VM allocation and allocator-internal operations outside the intercepted boundaries are out of scope.
- The driver checks exact checksums for the paired operations, expected guard and arithmetic failures, branch counts, immutable prior state, FIFO protocol and counter graph cardinality. A completed timing run is performance evidence for its input. Machine and checker correctness continue to use the project’s own verification.
