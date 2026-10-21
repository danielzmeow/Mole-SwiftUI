# Mole SwiftUI adapter

Native macOS 26+ shell for Mole CLI (macOS). The upstream CLI stays at the repository root; all Swift sources live here. This is a separate SwiftUI shell, not the upstream Mole Mac product.

## Run

Requires full Xcode, Python 3 and Go 1.26+. The scripts use `/Applications/Xcode.app` when `DEVELOPER_DIR` is unset, without changing the machine's selected developer directory. From the repository root:

```bash
./script/build_and_run.sh
./script/build_and_run.sh --build-only
./script/build_and_run.sh --verify
./script/test_adapter.sh
```

`GO=/absolute/path/to/go ./script/build_and_run.sh` can select a local Go toolchain. The script builds a local, ad hoc signed `dist/MoleShell.app`, including the unmodified CLI scripts, license, and locally built Go helpers. It does not install or update the user's Mole. This is a development bundle; distribution signing and notarization are not configured.

An optional project-local Go toolchain at `macos/.build/toolchains/go` is used when Go is absent from PATH. This checkout has a verified official Go 1.26.0 toolchain prepared there; it is ignored build tooling, never part of the app bundle or source commit. Go caches also default to `macos/.build/`.

The interface targets macOS 26+ for native Liquid Glass controls. `emil-design-eng` governs visual hierarchy, spacing and responsive feedback; the macOS Liquid Glass skill governs system materials and toolbar grouping. Navigation and keyboard actions have no custom animations. The adapter still uses the same four read-only command surfaces.

The current visual direction uses neutral content, system accent controls and flat sections. Custom rounded cards, colored icon tiles, promotional copy and repeated explanatory subtitles are removed.

## Compatibility

`Compatibility.json` pins the supported CLI version and reviewed source commit. The app checks executable `mo` / `mole` candidates from absolute PATH directories, Homebrew's standard prefixes and `~/.local/bin`, without executing a login shell. Only an exact stable version is accepted; older, newer, nightly, unknown and failed version probes fall back to the bundled CLI. If the bundle cannot be verified, the app stops. A command failure never triggers fallback or retry.

Selection is performed on launch and can be repeated in Settings. A replacement of an installed executable after selection is not identity-pinned in this initial read-only adapter; any future destructive command needs execution-time identity/version validation as part of its review.

## Available interfaces

| Native surface | CLI call | Scope |
| --- | --- | --- |
| System status | `mo status --json` | Explicit snapshots, summary cards and expandable native fields for all metrics |
| Disk analysis | `mo analyze --json [absolute-path]` | Overview, folder picker, directory navigation, filtering, large files; partial and unavailable sizes retained |
| Applications | `mo uninstall --list` | Searchable read-only inventory; no uninstall action |
| History | `mo history --json --limit 200` | Sessions, attribution, action counts, deletion outcomes and log locations |

Other command destinations explain the missing interface. The full gap registry and implementation constraints live in [AGENTS.md](../AGENTS.md#swiftui-adapter-contract). No terminal embedding, TUI-frame parsing, simulated input, privilege helper, duplicated cleanup policy or direct deletion is implemented.

The process client passes argument arrays directly, disconnects stdin, drains both output streams, bounds output and wall time, and cancels its owned process group. Test/debug CLI environment overrides are removed. CLI diagnostics and nonzero exits are visible. Completed snapshots remain visible after a failed refresh, with their previous read time.

## Periodic upstream synchronization

Synchronization is manual for now; this does not install a background scheduler or enable runtime downloads.

1. Review upstream changes since `Compatibility.json.sourceCommit`, especially the four production consumers above. Keep SwiftUI edits outside upstream CLI paths.
2. Update the version/source receipt only after checking command flags, JSON shapes and the gap registry. The staging script refuses CLI source drift against that receipt.
3. Run Swift adapter tests, build the bundle, verify each read-only interface against the bundled CLI and test installed/fallback selection. Run the upstream required checks if any upstream CLI code changes.
4. Revisit pending rows in `AGENTS.md`; missing interfaces remain skipped until explicitly discussed. Record dated evidence here without claiming a published release.

Initial source baseline: `84dc779dc651ff1f0509a2054b6e25b8fb5d2ac5`, CLI version `1.62.0`. Verification receipts are added after local checks below.

Local verification, 2026-10-21 (Asia/Taipei): the SwiftUI app builds with full Xcode and launches as an ad hoc signed `.app`. All 10 adapter fixture tests passed; the separately enabled integration test passed against the bundled CLI for version, status, temporary-folder analysis, app inventory and history. `check.sh --format` and `check.sh --no-format` completed; the latter used `go vet` because golangci-lint is absent, skipped unavailable ShellCheck and skipped the Windows skill comparison because `origin/windows` is absent. Shell syntax, Python compilation, plist and code-signature checks passed. No upstream CLI source was changed. Full upstream Bats tests and distribution signing/notarization have not been run.
