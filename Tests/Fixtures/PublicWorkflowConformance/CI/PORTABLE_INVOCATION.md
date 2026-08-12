# Public workflow evidence invocation

The validation corpus invokes the platform runner from a checkout of the SwiftTLA implementation:

```sh
scripts/run_public_workflow_platform_matrix.sh --output <relative-output-root> --context <relative-binding-context.json>
```

`binding-context.json` contains only project-relative source and configuration paths, their SHA-256 digests, and declared provenance pins. The runner verifies those paths and digests before executing `xcodebuild`. The output is self-contained beneath `<relative-output-root>` and can be uploaded or exported without a local development path.

GitHub Actions runs this contract as the hosted source of truth: it retains exact commands, inputs, logs, results, and SHA-256 files in its uploaded artifact, and fails when any declared outcome fails. A complete retained hosted-workflow record can support this repository's declared bounded checks; local invocations, including a spoofed environment, remain diagnostic only. A future SwiftTLA-Validation corpus can retrieve and evaluate the portable artifact without relying on local development paths.
