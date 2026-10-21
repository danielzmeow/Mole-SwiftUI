#!/usr/bin/env bats

load helpers/common

setup() {
    mole_test_setup_home clean-json
}

teardown() {
    mole_test_teardown_home
}

@test "clean JSON help describes a read-only path preview without scanning" {
    run bash -c '"$PROJECT_ROOT/mole" clean --json --help > "$HOME/result.json"'
    [ "$status" -eq 0 ] || return 1
    run python3 -c 'import json,os; p=json.load(open(os.environ["HOME"]+"/result.json")); assert p["schema_version"]==2 and p["mode"]=="preview" and p["execution_supported"] is True'
    [ "$status" -eq 0 ] || return 1
    [ ! -e "$HOME/.config/mole/clean-list.txt" ] || return 1
}

@test "clean JSON refuses execution and incompatible modes before discovery" {
    local arguments
    for arguments in '--json' '--json --whitelist' '--whitelist --json' '--json --dry-run --external /tmp'; do
        # shellcheck disable=SC2086  # Fixed argument vectors intentionally exercise each parser combination.
        run "$PROJECT_ROOT/mole" clean $arguments
        [ "$status" -ne 0 ] || return 1
        [[ "$output" == *"JSON"* || "$output" == *"external"* ]] || return 1
        [ ! -e "$HOME/.config/mole/clean-list.txt" ] || return 1
    done
}

@test "clean JSON uses guarded preview ledger with overlap and unknown sizes" {
    run bash <<'SCRIPT'
source "$PROJECT_ROOT/bin/clean.sh"
perform_cleanup() {
    CURRENT_SECTION='User essentials'
    root="$HOME/Library/Caches/parent"
    odd="$HOME/Library/Caches/"$'缓存"\t\n'
    mkdir -p "$root/child" "$odd"
    _MOLE_DRY_RUN_TARGET_PREVALIDATED=true
    record_dry_run_cleanup_target "$root" 8 1 true
    record_dry_run_cleanup_target "$root/child" 4 2 true
    record_dry_run_cleanup_target "$root" 8 1 true
    record_dry_run_cleanup_target "$odd" 0 1 false
    _MOLE_DRY_RUN_TARGET_PREVALIDATED=false
    # Real protected-path guard must reject a target even in preview.
    if record_dry_run_cleanup_target "$HOME/.gitconfig.lock" 99 1 true; then return 99; fi
    render_clean_preview_from_ledger
}
main --dry-run --json > "$HOME/result.json" 2> "$HOME/diagnostics"
SCRIPT
    [ "$status" -eq 0 ] || { cat "$HOME/diagnostics"; return 1; }
    run python3 <<'PY'
import json, os
from pathlib import Path
home = Path(os.environ['HOME'])
p = json.loads((home/'result.json').read_text())
assert p['total_size_bytes'] == 8192 and p['total_items'] == 2
assert p['size_partial'] and not p['system_included']
assert len(p['entries']) == 3
assert p['entries'][1]['counted_under'].endswith('/parent')
assert p['entries'][2]['path'].endswith('缓存"\t\n')
assert p['entries'][2]['size_bytes'] is None
assert (home/'Library/Caches/parent/child').is_dir()
assert not (home/'.config/mole/clean-list.txt').exists()
PY
    [ "$status" -eq 0 ] || return 1
}

@test "clean JSON never publishes successful output after scan failure or cancellation" {
    local failure
    for failure in 1 130 143; do
        run env FAILURE="$failure" bash <<'SCRIPT'
source "$PROJECT_ROOT/bin/clean.sh"
perform_cleanup() { printf 'diagnostic\n'; return "$FAILURE"; }
main --dry-run --json > "$HOME/result.json" 2> "$HOME/diagnostics"
SCRIPT
        [ "$status" -eq "$failure" ] || return 1
        [ ! -s "$HOME/result.json" ] || return 1
        [ -s "$HOME/diagnostics" ] || return 1
    done
}

@test "clean JSON rejects a truncated ledger rather than publishing partial rows" {
    run bash <<'SCRIPT'
source "$PROJECT_ROOT/bin/clean.sh"
source "$PROJECT_ROOT/lib/clean/preview_json.sh"
emit_deduplicated_dry_run_ledger() { printf 'path\0broken\0'; }
emit_clean_preview_json > "$HOME/result.json"
SCRIPT
    [ "$status" -ne 0 ] || return 1
    [ ! -s "$HOME/result.json" ] || return 1
}
