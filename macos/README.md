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

`GO=/absolute/path/to/go ./script/build_and_run.sh` can select a local Go toolchain. The script builds a local, ad hoc signed `dist/MoleShell.app`, including the reviewed CLI scripts, the authorized clean preview extension, license, and locally built Go helpers. It does not install or update the user's Mole. This is a development bundle; distribution signing and notarization are not configured.

An optional project-local Go toolchain at `macos/.build/toolchains/go` is used when Go is absent from PATH. This checkout has a verified official Go 1.26.0 toolchain prepared there; it is ignored build tooling, never part of the app bundle or source commit. Go caches also default to `macos/.build/`.

The interface targets macOS 26+ for native Liquid Glass controls. `emil-design-eng` governs visual hierarchy, spacing and responsive feedback; the macOS Liquid Glass skill governs system materials and toolbar grouping. Navigation and keyboard actions have no custom animations. The sidebar follows the five CLI main-menu entries, in order: Clean, Uninstall, Optimize, Analyze and Status, followed by History as the sixth entry. Status remains the initial selection.

The current visual direction uses neutral content, system accent controls and flat sections. Custom rounded cards, colored icon tiles, promotional copy and repeated explanatory subtitles are removed.

## Compatibility

`Compatibility.json` pins the supported CLI version and reviewed source commit. The app checks executable `mo` / `mole` candidates from absolute PATH directories, Homebrew's standard prefixes and `~/.local/bin`, without executing a login shell. An installed CLI must also pass the non-scanning `clean --json --help` capability probe for cleanup schema 2. Only an exact stable version is accepted; older, newer, nightly, unknown and failed version probes fall back to the bundled CLI. If the bundle cannot be verified, the app stops. A command failure never triggers fallback or retry.

Selection is performed on launch and can be repeated in Settings. The launcher and every shell source under the reported CLI root are hashed with file identities at connection. Cleanup rechecks those hashes, the stable version and capability immediately before execution. A source or connection change requires reconnecting and scanning again.

## Available interfaces

| Native surface | CLI call | Scope |
| --- | --- | --- |
| Clean | `mo clean --dry-run --json`; `mo clean --json --apply-selection FILE` | Path preview, explicit selection and confirmation, bounded user-level permanent cleanup and per-path results; unsupported paths stay read-only |
| System status | `mo status --json` | Explicit snapshots, summary cards and expandable native fields for all metrics |
| Disk analysis | `mo analyze --json [absolute-path]` | Overview, folder picker, directory navigation, filtering, large files; partial and unavailable sizes retained |
| Applications | `mo uninstall --list` | Searchable read-only inventory; no uninstall action |
| History | `mo history --json --limit 200` | Sessions, attribution, action counts, deletion outcomes and log locations |

Optimize shows a brief unavailable state until a reviewed structured interface exists. Uninstall remains a read-only inventory. History is retained; other auxiliary commands have no navigation entry. The full gap registry and implementation constraints live in [AGENTS.md](../AGENTS.md#swiftui-adapter-contract). The GUI does not embed terminals, parse TUI frames, simulate input, add a privilege helper, duplicate cleanup policy or delete filesystem targets directly; cleanup remains in the CLI.

The process client passes argument arrays directly, disconnects stdin, drains both output streams, bounds output and wall time, and cancels its owned process group. Test/debug CLI environment overrides are removed. CLI diagnostics and nonzero exits are visible. Completed snapshots remain visible after a failed refresh, with their previous read time.

## Periodic upstream synchronization

Synchronization is manual for now; this does not install a background scheduler or enable runtime downloads.

1. Review upstream changes since `Compatibility.json.sourceCommit`, especially the production consumers above and the retained history adapter. Keep SwiftUI edits outside upstream CLI paths.
2. Update the version/source receipt only after checking command flags, JSON shapes and the gap registry. The staging script refuses CLI source drift against that receipt, except for explicitly reviewed files with exact SHA-256 hashes in `sourceOverrides`.
3. Run Swift adapter tests, build the bundle, verify each read-only interface against the bundled CLI and test installed/fallback selection. Run the upstream required checks if any upstream CLI code changes.
4. Revisit pending rows in `AGENTS.md`; missing interfaces remain skipped until explicitly discussed. Record dated evidence here without claiming a published release.

Initial source baseline: `84dc779dc651ff1f0509a2054b6e25b8fb5d2ac5`, CLI version `1.62.0`. Verification receipts are added after local checks below.

Initial read-only baseline verification, 2026-10-21 (Asia/Taipei): the SwiftUI app builds with full Xcode and launches as an ad hoc signed `.app`. All 10 adapter fixture tests passed; the separately enabled integration test passed against the bundled CLI for version, status, temporary-folder analysis, app inventory and history. `check.sh --format` and `check.sh --no-format` completed; the latter used `go vet` because golangci-lint is absent, skipped unavailable ShellCheck and skipped the Windows skill comparison because `origin/windows` is absent. Shell syntax, Python compilation, plist and code-signature checks passed. No upstream CLI source was changed. Full upstream Bats tests and distribution signing/notarization have not been run.

## Clean preview and selection extension (2026-10-21)

The maintainer authorized a thin CLI machine interface for scanning and then selection/cleanup. `clean --dry-run --json` runs the existing dry-run pipeline and serializes its deduplicated NUL-delimited ledger; no terminal text is parsed and Swift does not copy cleanup policies. JSON stays on stdout and diagnostics go to stderr. System Perl, JSON::PP, MIME::Base64 and Encode are required; missing components fail visibly. Temporary text previews do not overwrite `~/.config/mole/clean-list.txt`. Normal dry-run logging remains enabled.

Schema 2 reports `coverage: path_candidates`, `execution_supported: true` and a CLI scan time. Entries carry section, absolute path, optional measured bytes, item count, an overlap ancestor and an optional opaque selection token. Covered rows remain visible without counting their bytes twice; unknown sizes stay null. `system_included` reports whether the existing non-prompting cached-sudo adoption included system discovery. This does not promise complete coverage of owner-command actions.

Only candidates emitted through the existing guarded `safe_clean` seam can receive selection tokens, and only while user-owned, non-symlinked and physically below HOME without symlinked ancestors. The native view starts with nothing selected, supports whole-row disclosure, individual checkboxes and selecting all supported candidates. Parent selection includes all its contents; children cannot express exclusions from a selected parent. Confirmation explicitly names every selected path and states that deletion is permanent. Direct-record candidates, including Trash, and administrator/owner-tool actions remain read-only.

`clean --json --apply-selection FILE` accepts schema 2 selection tokens from a preview no older than 30 minutes (up to 1000 non-overlapping paths). Tokens carry the path, section, physical parent, device/inode identities and target mtime. They are bindings, not signatures or stored authorization. Execution reruns normal discovery in dry-run and can act only when an exact selected path is rediscovered at the supported seam. It then rechecks identity, invokes the original family guard with real-mode semantics while its dynamic inputs are alive, and calls existing `safe_remove` with the preview parent/target identity binding. Whitelist, compiled-model, live-owner, SQLite, path validation and final-sink checks remain owned by the CLI. No elevated delete or fallback sink is added. Everything outside this seam remains in dry-run, so unselected paths and owner-command actions do not execute.

A per-selection claim prevents duplicate discovery from executing twice. Sink/guard cancellation writes shared stop state so later selections cannot run, even across discovery subprocesses. Results report removed, retained or interrupted paths; refused fresh candidates are logged as SKIPPED, completed sinks keep existing REMOVED logging, and the real session summary counts only completed selected paths. The byte summary uses the pre-removal measurement, not APFS free-space change. A directory selection authorizes its contents, not a frozen recursive file inventory; the final existing guards are point-in-time checks rather than a cross-process lock.

The adapter pins CLI source identity and version before execution and never retries with another CLI. The current scan is consumed before execution; interruption, timeout, nonzero exit or invalid output requires a new scan and warns that some selected paths may already have been removed. The UI uses indeterminate feedback rather than machine phase streaming. `clean --json --help` describes the capability without scanning. External volumes and whitelist editing are refused in JSON mode. The base receipt remains at the reviewed upstream commit; the four local CLI extension files have exact SHA-256 receipts in `Compatibility.json`. This is a local development extension, not an upstream release.

Selection-cleanup verification, 2026-10-21 (Asia/Taipei): the app builds and launches through `script/build_and_run.sh`. Native-window checks covered a real scan, clicking the disclosure text, selecting a checkbox, reviewing the exact-path permanent-deletion sheet, cancelling and clearing selection. Real deletion was verified only inside isolated test HOME directories through the production guard and `safe_remove` sink. The final 14 JSON/selection Bats cases passed, covering protected paths, overlap accounting, unknown sizes, changed target/parent identities, symlinks, whitelist changes, real-mode family guards, out-of-discovery input, expired selections and sticky sink-timeout cancellation. Swift Testing reported a passing run of 16 tests, including one disabled optional integration smoke; the four staging-receipt tests passed. ShellCheck, shell/Python syntax, `go vet`, formatting and the duplication, destructive-sink, timeout and assertion audits passed. The Windows skill comparison remains unavailable because `origin/windows` is absent; golangci-lint is unavailable, so the check script used `go vet`.

The full test runner completed rather than being stopped early. Its Bats summary was `2630 tests, 32 failures, 13 skipped`; all 32 failing cases also failed against the unchanged `987c6815` baseline in this environment (including process/TTY, install/update locks, cloud-cache and optimize/uninstall fixture cases). A separate `go test ./...` confirmed the Go-test failure comes from the sandbox denying a test Trash move and three `/bin/ps` integration probes; no Go sources were changed. No unrelated baseline tests or safety guards were weakened to obtain a green run. This is a development bundle, not a release; no real user cleanup was executed during verification.
