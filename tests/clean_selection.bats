#!/usr/bin/env bats

load helpers/common

setup() {
    mole_test_setup_home clean-selection
    mkdir -p "$HOME/Library/Caches/NativeSelectionFixture"
    printf 'selected data\n' > "$HOME/Library/Caches/NativeSelectionFixture/a"
    printf 'keep data\n' > "$HOME/Library/Caches/NativeSelectionFixture/b"
    # Only replace orchestration with two exact fixture candidates. The real
    # safe_clean/guard, recorder, identity binding, safe_remove and logs run.
    cat > "$HOME/driver" <<'SCRIPT'
source "$PROJECT_ROOT/bin/clean.sh"
selection_fixture_guard() {
    if [[ "$DRY_RUN" != true ]]; then
        printf '%s\n' "$1" >> "$HOME/real-guard"
        [[ "${DENY_REAL_GUARD:-0}" != 1 ]] || return 1
    fi
    return 0
}
perform_cleanup() {
    CURRENT_SECTION='Selection fixture'
    safe_clean_guarded selection_fixture_guard \
        "$HOME/Library/Caches/NativeSelectionFixture/a" \
        "$HOME/Library/Caches/NativeSelectionFixture/b" 'Fixture'
    if [[ -z "${CLEAN_APPLY_FILE:-}" ]]; then render_clean_preview_from_ledger; fi
}
main "$@"
SCRIPT
}

teardown() {
    mole_test_teardown_home
}

scan_and_select_a() {
    # shellcheck disable=SC2016  # The child shell must expand its isolated HOME.
    run env MOLE_TEST_NO_AUTH=1 bash -c 'bash "$HOME/driver" --dry-run --json > "$HOME/preview.json" 2> "$HOME/scan.log"'
    [ "$status" -eq 0 ] || { cat "$HOME/scan.log"; return 1; }
    run python3 <<'PY'
import json, os
from pathlib import Path
home = Path(os.environ['HOME'])
p = json.loads((home/'preview.json').read_text())
tokens = [e['selection_token'] for e in p['entries'] if e['path'].endswith('/a')]
assert len(tokens) == 1 and tokens[0]
(home/'selection.json').write_text(json.dumps({'schema_version':2,'created_at':p['created_at'],'selections':tokens}))
PY
    [ "$status" -eq 0 ] || { printf '%s\n' "$output"; return 1; }
}

apply_selection() {
    # shellcheck disable=SC2016  # The child shell must expand its isolated HOME.
    run env MOLE_TEST_NO_AUTH=1 DENY_REAL_GUARD="${DENY_REAL_GUARD:-0}" bash -c \
        'bash "$HOME/driver" --json --apply-selection "$HOME/selection.json" > "$HOME/result.json" 2> "$HOME/apply.log"'
}

@test "native selection removes only the selected rediscovered candidate through real sink" {
    scan_and_select_a
    apply_selection
    [ "$status" -eq 0 ] || { cat "$HOME/apply.log"; return 1; }
    [ ! -e "$HOME/Library/Caches/NativeSelectionFixture/a" ] || return 1
    [ -f "$HOME/Library/Caches/NativeSelectionFixture/b" ] || return 1
    [ -s "$HOME/real-guard" ] || return 1
    run python3 <<'PY'
import json,os
from pathlib import Path
h=Path(os.environ['HOME']); p=json.loads((h/'result.json').read_text())
assert len(p['results'])==1 and p['results'][0]['status']=='removed'
logs=(h/'Library/Logs/mole/operations.log').read_text()
assert 'REMOVED' in logs and 'NativeSelectionFixture/a' in logs
PY
    [ "$status" -eq 0 ] || { printf '%s\n' "$output"; return 1; }
}

@test "native selection refuses a replaced inode without touching its replacement or sibling" {
    scan_and_select_a
    mv "$HOME/Library/Caches/NativeSelectionFixture/a" "$HOME/original-a"
    printf 'replacement\n' > "$HOME/Library/Caches/NativeSelectionFixture/a"
    apply_selection
    [ "$status" -eq 0 ] || return 1
    [ -f "$HOME/Library/Caches/NativeSelectionFixture/a" ] || return 1
    [ -f "$HOME/Library/Caches/NativeSelectionFixture/b" ] || return 1
    run python3 -c 'import json,os; p=json.load(open(os.environ["HOME"]+"/result.json")); assert p["results"][0]["reason"]=="identity_changed"'
    [ "$status" -eq 0 ] || return 1
}

@test "native selection rechecks the family guard with real semantics" {
    scan_and_select_a
    DENY_REAL_GUARD=1
    apply_selection
    [ "$status" -eq 0 ] || return 1
    [ -f "$HOME/Library/Caches/NativeSelectionFixture/a" ] || return 1
    [ -f "$HOME/Library/Caches/NativeSelectionFixture/b" ] || return 1
    [ -s "$HOME/real-guard" ] || return 1
    run python3 -c 'import json,os; p=json.load(open(os.environ["HOME"]+"/result.json")); assert p["results"][0]["reason"]=="guard_refused"'
    [ "$status" -eq 0 ] || return 1
}

@test "native selection cannot authorize a path absent from fresh discovery" {
    scan_and_select_a
    run python3 <<'PY'
import base64,json,os
from pathlib import Path
h=Path(os.environ['HOME']); p=json.loads((h/'selection.json').read_text())
r=json.loads(base64.b64decode(p['selections'][0])); r['path']=str(h/'unrelated')
(h/'unrelated').write_text('keep')
p['selections']=[base64.b64encode(json.dumps(r).encode()).decode()]
(h/'selection.json').write_text(json.dumps(p))
PY
    [ "$status" -eq 0 ] || return 1
    apply_selection
    [ "$status" -eq 0 ] || return 1
    [ -f "$HOME/unrelated" ] || return 1
    [ -f "$HOME/Library/Caches/NativeSelectionFixture/a" ] || return 1
    run python3 -c 'import json,os; p=json.load(open(os.environ["HOME"]+"/result.json")); assert p["results"][0]["reason"]=="not_eligible"'
    [ "$status" -eq 0 ] || return 1
}

@test "native selection refuses an expired plan before entering cleanup" {
    scan_and_select_a
    run python3 -c 'import json,os; f=os.environ["HOME"]+"/selection.json"; p=json.load(open(f)); p["created_at"]=1; open(f,"w").write(json.dumps(p))'
    [ "$status" -eq 0 ] || return 1
    apply_selection
    [ "$status" -ne 0 ] || return 1
    [ -f "$HOME/Library/Caches/NativeSelectionFixture/a" ] || return 1
    [ ! -e "$HOME/real-guard" ] || return 1
}

@test "native selection binds the physical parent as well as the selected inode" {
    scan_and_select_a
    mv "$HOME/Library/Caches/NativeSelectionFixture" "$HOME/original-parent"
    mkdir "$HOME/Library/Caches/NativeSelectionFixture"
    mv "$HOME/original-parent/a" "$HOME/Library/Caches/NativeSelectionFixture/a"
    apply_selection
    [ "$status" -eq 0 ] || return 1
    [ -f "$HOME/Library/Caches/NativeSelectionFixture/a" ] || return 1
    run python3 -c 'import json,os; p=json.load(open(os.environ["HOME"]+"/result.json")); assert p["results"][0]["reason"]=="identity_changed"'
    [ "$status" -eq 0 ] || return 1
}

@test "native selection refuses a symlink replacement without touching its destination" {
    scan_and_select_a
    mv "$HOME/Library/Caches/NativeSelectionFixture/a" "$HOME/original-a"
    ln -s "$HOME/Library/Caches/NativeSelectionFixture/b" "$HOME/Library/Caches/NativeSelectionFixture/a"
    apply_selection
    [ "$status" -eq 0 ] || return 1
    [ -L "$HOME/Library/Caches/NativeSelectionFixture/a" ] || return 1
    [ -f "$HOME/Library/Caches/NativeSelectionFixture/b" ] || return 1
}

@test "native selection preserves unrelated paths when fresh whitelist protection changes" {
    scan_and_select_a
    mkdir -p "$HOME/.config/mole"
    printf '%s\n' "$HOME/Library/Caches/NativeSelectionFixture/a" > "$HOME/.config/mole/whitelist"
    apply_selection
    [ "$status" -eq 0 ] || return 1
    [ -f "$HOME/Library/Caches/NativeSelectionFixture/a" ] || return 1
    [ -f "$HOME/Library/Caches/NativeSelectionFixture/b" ] || return 1
    run python3 -c 'import json,os; p=json.load(open(os.environ["HOME"]+"/result.json")); assert p["results"][0]["reason"]=="not_eligible"'
    [ "$status" -eq 0 ] || return 1
}

@test "native selection sink timeout stops a later otherwise eligible selection" {
    scan_and_select_a
    run python3 <<'PY'
import json,os
from pathlib import Path
h=Path(os.environ['HOME']); p=json.loads((h/'preview.json').read_text())
tokens=[e['selection_token'] for e in p['entries']]
assert len(tokens)==2 and all(tokens)
(h/'selection.json').write_text(json.dumps({'schema_version':2,'created_at':p['created_at'],'selections':tokens}))
driver=h/'driver'
s=driver.read_text().replace('main "$@"', '''safe_remove() { printf '%s\\n' "$1" >> "$HOME/sink-trace"; return 124; }
main "$@"''')
driver.write_text(s)
PY
    [ "$status" -eq 0 ] || { printf '%s\n' "$output"; cat "$HOME/apply.log"; return 1; }
    apply_selection
    [ "$status" -eq 0 ] || { printf '%s\n' "$output"; cat "$HOME/apply.log"; return 1; }
    [ -f "$HOME/Library/Caches/NativeSelectionFixture/a" ] || return 1
    [ -f "$HOME/Library/Caches/NativeSelectionFixture/b" ] || return 1
    run python3 <<'PY'
import json,os
from pathlib import Path
h=Path(os.environ['HOME']); p=json.loads((h/'result.json').read_text())
assert p['interrupted'] and len(p['results'])==2, p
assert p['results'][0]['status']=='failed' and p['results'][1]['status']=='retained'
assert (h/'sink-trace').read_text().splitlines()==[str(h/'Library/Caches/NativeSelectionFixture/a')], (h/'sink-trace').read_text()
PY
    [ "$status" -eq 0 ] || { printf '%s\n' "$output"; cat "$HOME/apply.log"; return 1; }
}
