# API baselines

`OklchCore.json` and `OklchUI.json` are `xcrun swift-api-digester -dump-sdk`
dumps of each module's public API surface, used by `check.sh` step 6 to fail
the gate on an unintended public-API change (see the comment in `check.sh`
for the exact invocation and why `ABIRoot.tool_arguments` is stripped before
comparing).

Because that stripped `tool_arguments` field is the only place the dump
records anything about the toolchain that produced it, the committed JSON
itself carries no version information. Recorded here instead, so a future
cross-toolchain diff is interpretable rather than mysterious:

- **Xcode**: 26.6 (build 17F113)
- **Swift**: Apple Swift version 6.3.3 (swiftlang-6.3.3.1.3 clang-2100.1.1.101)
- **SDK**: MacOSX SDK build 25F70 (`xcrun --show-sdk-path` reports
  `.../MacOSX.sdk`, `xcrun --show-sdk-version` reports `26.5`)
- **Host architecture**: arm64 (Apple silicon)
- **`-target`**: `arm64-apple-macos14.0` — `check.sh` passes
  `$(uname -m)-apple-macos14.0` so the gate also works unmodified on an
  Intel Mac, but these specific baseline files were generated on arm64. If
  step 6 ever fails on an x86_64 host with a diff that looks like
  architecture noise rather than a real API change, that mismatch — not a
  code change — is the first thing to check.

To re-record after an intentional public-API change:

```bash
for MODULE in OklchCore OklchUI; do
  swift build --target "$MODULE"
  xcrun swift-api-digester -dump-sdk -module "$MODULE" \
      -o "/tmp/baseline-$MODULE-raw.json" \
      -I .build/debug/Modules -sdk "$(xcrun --show-sdk-path)" \
      -target "$(uname -m)-apple-macos14.0"
  jq 'del(.ABIRoot.tool_arguments)' "/tmp/baseline-$MODULE-raw.json" \
      > "docs/api-baseline/$MODULE.json"
done
```

Update this README's toolchain versions at the same time if they changed.
