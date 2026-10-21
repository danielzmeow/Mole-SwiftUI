#!/bin/bash
# Selected native cleanup re-enters the existing guarded safe_clean call sites.
# Everything outside that exact seam stays in dry-run, including owner tools.

native_clean_snapshot() {
    local path="$1"
    [[ "$path" == "$HOME/"* && -O "$path" && ! -L "$path" ]] || return 1
    _mole_snapshot_path_identity "$path" || return 1
    local home_physical
    home_physical=$(cd -P "$HOME" && pwd -P) || return 1
    [[ "$_MOLE_PATH_SNAPSHOT_PARENT" == "$home_physical" ||
        "$_MOLE_PATH_SNAPSHOT_PARENT" == "$home_physical/"* ]] || return 1
    # Symlinked ancestors must not redirect a selected user path elsewhere.
    [[ "$_MOLE_PATH_SNAPSHOT_PARENT" == "${path%/*}" ]] || return 1
    _MOLE_NATIVE_IDENTITY=$(mole_deletion_identity "$path") || return $?
}

record_safe_clean_preview_target() {
    local path="$1" size_kb="$2" count="$3" known="$4" guard="$5" deadline="$6"
    if [[ "${CLEAN_JSON:-false}" != "true" ]]; then
        record_dry_run_cleanup_target "$path" "$size_kb" "$count" "$known"
        return $?
    fi
    if [[ -f "${CLEAN_NATIVE_STATE:-}/cancelled" ]]; then
        return 130
    fi
    local parent="" parent_id="" target_id="" identity=""
    # Capture before the recorder does potentially slow safety probes.
    if native_clean_snapshot "$path"; then
        parent="$_MOLE_PATH_SNAPSHOT_PARENT"
        parent_id="$_MOLE_PATH_SNAPSHOT_PARENT_ID"
        target_id="$_MOLE_PATH_SNAPSHOT_TARGET_ID"
        identity="$_MOLE_NATIVE_IDENTITY"
    fi
    record_dry_run_cleanup_target "$path" "$size_kb" "$count" "$known" || return $?
    [[ -n "$parent" ]] || return 0
    _mole_path_matches_identity "$path" "$parent" "$parent_id" "$target_id" || return 0
    [[ "$(mole_deletion_identity "$path")" == "$identity" ]] || return 0
    if [[ -n "${CLEAN_APPLY_FILE:-}" ]]; then
        native_clean_apply_at_sink "$path" "$size_kb" "$known" "$guard" "$deadline"
    else
        printf '%s\0%s\0%s\0%s\0%s\0%s\0' "$path" "${CURRENT_SECTION:-Uncategorized}" \
            "$parent" "$parent_id" "$target_id" "$identity" >> "$CLEAN_NATIVE_ACTIONS"
    fi
}

prepare_native_clean_selection() {
    CLEAN_NATIVE_STATE=$(create_temp_dir) || return 1
    CLEAN_NATIVE_ACTIONS=$(create_temp_file) || return 1
    : > "$CLEAN_NATIVE_ACTIONS"
    CLEAN_SELECTED_PATHS=()
    CLEAN_SELECTED_SECTIONS=()
    CLEAN_SELECTED_PARENTS=()
    CLEAN_SELECTED_PARENT_IDS=()
    CLEAN_SELECTED_TARGET_IDS=()
    CLEAN_SELECTED_IDENTITIES=()
    [[ -n "${CLEAN_APPLY_FILE:-}" ]] || return 0
    local parsed
    parsed=$(create_temp_file) || return 1
    /usr/bin/perl -MJSON::PP -MMIME::Base64=decode_base64 -MEncode=encode -e '
        use strict; use warnings;
        my $file = shift;
        die "Selection exceeds input limit\n" unless -f $file && -s $file <= 2_000_000;
        open my $fh, "<", $file or die "Cannot read selection\n";
        local $/; my $input = <$fh>;
        my $plan = JSON::PP->new->utf8->decode($input);
        die "Unsupported selection contract\n" unless $plan->{schema_version} == 2 && ref($plan->{selections}) eq "ARRAY";
        die "Expired preview; scan again\n" unless $plan->{created_at} =~ /^\d+$/ && time - $plan->{created_at} <= 1800 && $plan->{created_at} <= time + 60;
        die "Select between 1 and 1000 candidates\n" unless @{$plan->{selections}} && @{$plan->{selections}} <= 1000;
        my @rows; my %seen;
        for my $token (@{$plan->{selections}}) {
            die "Invalid selection token\n" if ref($token) || length($token) > 32768 || $token !~ m{\A[A-Za-z0-9+/]+=*\z};
            my $row = JSON::PP->new->utf8->decode(decode_base64($token));
            for my $key (qw(path section parent parent_id target_id identity)) {
                die "Invalid candidate field\n" if !defined($row->{$key}) || ref($row->{$key}) || $row->{$key} =~ /\0/;
            }
            die "Invalid candidate identity\n" unless $row->{path} =~ m{^/} && $row->{parent} =~ m{^/}
                && $row->{parent_id} =~ /^\d+:\d+$/ && $row->{target_id} =~ /^\d+:\d+$/ && $row->{identity} =~ /^\d+:\d+:-?\d+$/;
            die "Duplicate candidate\n" if $seen{$row->{path}}++;
            push @rows, $row;
        }
        for my $a (@rows) { for my $b (@rows) {
            die "Overlapping selections; select the parent or its children\n" if index($b->{path}, $a->{path}."/") == 0;
        }}
        binmode STDOUT;
        for my $row (@rows) { print encode("UTF-8", join("\0", @{$row}{qw(path section parent parent_id target_id identity)})), "\0"; }
    ' "$CLEAN_APPLY_FILE" > "$parsed" || return 1
    local path section parent parent_id target_id identity
    while IFS= read -r -d '' path && IFS= read -r -d '' section &&
        IFS= read -r -d '' parent && IFS= read -r -d '' parent_id &&
        IFS= read -r -d '' target_id && IFS= read -r -d '' identity; do
        CLEAN_SELECTED_PATHS+=("$path")
        CLEAN_SELECTED_SECTIONS+=("$section")
        CLEAN_SELECTED_PARENTS+=("$parent")
        CLEAN_SELECTED_PARENT_IDS+=("$parent_id")
        CLEAN_SELECTED_TARGET_IDS+=("$target_id")
        CLEAN_SELECTED_IDENTITIES+=("$identity")
    done < "$parsed"
    [[ ${#CLEAN_SELECTED_PATHS[@]} -gt 0 ]]
}

native_clean_apply_at_sink() {
    local path="$1" size_kb="$2" known="$3" guard="$4" deadline="$5"
    local index=0 selected
    for selected in "${CLEAN_SELECTED_PATHS[@]}"; do
        if [[ "$selected" == "$path" && "${CLEAN_SELECTED_SECTIONS[$index]}" == "${CURRENT_SECTION:-Uncategorized}" ]]; then
            break
        fi
        index=$((index + 1))
    done
    [[ $index -lt ${#CLEAN_SELECTED_PATHS[@]} ]] || return 0
    # A duplicate discovery, including a timeout subprocess, may not execute twice.
    mkdir "$CLEAN_NATIVE_STATE/$index.claim" 2> /dev/null || return 0
    local result="$CLEAN_NATIVE_STATE/$index.result"
    printf 'failed\0interrupted\0%s\0' 0 > "$result"
    local parent="${CLEAN_SELECTED_PARENTS[$index]}"
    local parent_id="${CLEAN_SELECTED_PARENT_IDS[$index]}"
    local target_id="${CLEAN_SELECTED_TARGET_IDS[$index]}"
    local identity="${CLEAN_SELECTED_IDENTITIES[$index]}"
    local rc=0 reason=""
    if ! _mole_path_matches_identity "$path" "$parent" "$parent_id" "$target_id" ||
        [[ "$(mole_deletion_identity "$path")" != "$identity" ]]; then
        reason="identity_changed"
    elif ! native_clean_snapshot "$path"; then
        reason="unsupported_scope"
    else
        # Re-run the original family guard with real-mode semantics and its
        # dynamically scoped inputs still alive. Do not replay a stored callback.
        if [[ -n "$guard" ]]; then
            DRY_RUN=false MOLE_DRY_RUN=0 "$guard" "$path" || rc=$?
        fi
        if [[ $rc -eq 0 ]]; then
            # Reuse the permanent cleanup funnel with the preview parent/inode
            # binding. This call never elevates and never invokes another CLI.
            DRY_RUN=false MOLE_DRY_RUN=0 safe_remove "$path" true "$size_kb" "$deadline" \
                "$parent" "$parent_id" "$target_id" || rc=$?
            if [[ $rc -eq 0 && ! -e "$path" && ! -L "$path" ]]; then
                printf 'removed\0completed\0%s\0' "$size_kb" > "$result"
                return 0
            fi
            reason="sink_refused_or_failed"
        else
            reason="guard_refused"
        fi
    fi
    if [[ "$reason" != "sink_refused_or_failed" ]]; then
        MOLE_DRY_RUN=0 log_operation clean SKIPPED "$path" "$reason"
    fi
    local outcome="retained"
    [[ "$reason" != "sink_refused_or_failed" ]] || outcome="failed"
    printf '%s\0%s\0%s\0' "$outcome" "$reason" 0 > "$result"
    if mole_rc_timeout_or_signal "$rc"; then
        : > "$CLEAN_NATIVE_STATE/cancelled"
        _mole_record_clean_cancellation "$rc"
        return "$rc"
    fi
    return 0
}

emit_native_clean_result() {
    local selection_file="$CLEAN_NATIVE_STATE/selected"
    local index=0 path outcome removed=0 measured_kb=0 item_kb reason
    for path in "${CLEAN_SELECTED_PATHS[@]}"; do
        if [[ ! -f "$CLEAN_NATIVE_STATE/$index.result" ]]; then
            MOLE_DRY_RUN=0 log_operation clean SKIPPED "$path" "not eligible in fresh discovery"
        else
            outcome=""
            {
                IFS= read -r -d '' outcome && IFS= read -r -d '' reason && IFS= read -r -d '' item_kb
            } < "$CLEAN_NATIVE_STATE/$index.result" || true
            if [[ "$outcome" == "removed" ]]; then
                removed=$((removed + 1))
                [[ "$item_kb" =~ ^[0-9]+$ ]] && measured_kb=$((measured_kb + item_kb))
            fi
        fi
        index=$((index + 1))
    done
    MOLE_DRY_RUN=0 log_operation_session_end clean "$removed" "$measured_kb"
    printf '%s\0' "${CLEAN_SELECTED_PATHS[@]}" > "$selection_file"
    /usr/bin/perl -MJSON::PP -MEncode=decode,FB_CROAK -e '
        use strict; use warnings;
        my ($dir, $exit_code) = @ARGV;
        open my $fh, "<", "$dir/selected" or die "Missing selected paths\n";
        binmode $fh; local $/ = "\0";
        my @results; my $index = 0;
        while (defined(my $path = <$fh>)) {
            chomp $path;
            my ($status, $reason) = ("retained", "not_eligible");
            if (open my $result, "<", "$dir/$index.result") {
                $status = <$result>; $reason = <$result>;
                chomp $status; chomp $reason;
            }
            push @results, {path => decode("UTF-8", $path, FB_CROAK), status => $status, reason => $reason};
            ++$index;
        }
        print JSON::PP->new->utf8->canonical->encode({schema_version => 2, command => "clean",
            mode => "selection_result", interrupted => $exit_code != 0 ? JSON::PP::true : JSON::PP::false,
            results => \@results}), "\n";
    ' "$CLEAN_NATIVE_STATE" "${1:-0}"
}
