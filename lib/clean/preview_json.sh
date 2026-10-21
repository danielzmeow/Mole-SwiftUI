#!/bin/bash
# Structured path-candidate preview. Discovery and eligibility remain in clean.sh.

clean_preview_json_help() {
    /usr/bin/perl -MJSON::PP -MEncode=decode,FB_CROAK -e '
        print JSON::PP->new->utf8->canonical->encode({schema_version => 2, command => "clean",
            mode => "preview", coverage => "path_candidates", execution_supported => JSON::PP::true,
            source_root => decode("UTF-8", $ARGV[0], FB_CROAK)}), "\n";
    ' "$(cd "$SCRIPT_DIR/.." && pwd -P)"
}

emit_clean_preview_json() {
    local ledger
    ledger=$(create_temp_file) || return 1
    # Do not serialize partial producer output as a successful preview.
    emit_deduplicated_dry_run_ledger > "$ledger" || return 1
    # shellcheck disable=SC2154  # Aggregation counters are owned by the sourced clean orchestrator.
    /usr/bin/perl -MJSON::PP -MEncode=decode,FB_CROAK -MMIME::Base64=encode_base64 -e '
        use strict;
        use warnings;
        binmode STDIN;
        local $/ = "\0";
        my %actions;
        if (length($ARGV[5] // "")) {
            open my $actions, "<", $ARGV[5] or die "Missing action ledger\n";
            binmode $actions;
            while (defined(my $path = <$actions>)) {
                chomp $path;
                my @fields;
                for (1 .. 5) {
                    my $field = <$actions>;
                    die "Incomplete action ledger\n" unless defined $field && $field =~ s/\0$//;
                    push @fields, $field;
                }
                my ($section, $parent, $parent_id, $target_id, $identity) = @fields;
                my $row = {path => decode("UTF-8", $path, FB_CROAK), section => decode("UTF-8", $section, FB_CROAK),
                    parent => decode("UTF-8", $parent, FB_CROAK), parent_id => $parent_id, target_id => $target_id, identity => $identity};
                $actions{$row->{path}}{$row->{section}} = encode_base64(JSON::PP->new->utf8->canonical->encode($row), "");
            }
        }
        my @entries;
        while (defined(my $identity = <STDIN>)) {
            chomp $identity;
            my @fields;
            for (1 .. 6) {
                my $field = <STDIN>;
                die "Incomplete cleanup ledger\n" unless defined $field && $field =~ s/\0$//;
                push @fields, $field;
            }
            my ($kb, $count, $known, $section, $path, $covered) = @fields;
            die "Invalid cleanup ledger\n" unless $kb =~ /^\d+$/ && $count =~ /^\d+$/ && $known =~ /^(true|false)$/;
            my $decoded_path = decode("UTF-8", $path, FB_CROAK);
            my $decoded_section = decode("UTF-8", $section, FB_CROAK);
            push @entries, {
                path => $decoded_path,
                section => $decoded_section,
                selection_token => $actions{$decoded_path}{$decoded_section},
                size_bytes => $known eq "true" ? 1024 * $kb : undef,
                item_count => 0 + $count,
                counted_under => length($covered) ? decode("UTF-8", $covered, FB_CROAK) : undef,
            };
        }
        my ($total_kb, $items, $partial, $system, $sizing_timeouts) = @ARGV;
        my $result = {
            schema_version => 2, command => "clean", mode => "preview",
            created_at => time,
            coverage => "path_candidates", execution_supported => JSON::PP::true,
            system_included => $system eq "true" ? JSON::PP::true : JSON::PP::false,
            size_partial => ($partial eq "true" || $sizing_timeouts > 0) ? JSON::PP::true : JSON::PP::false,
            total_size_bytes => 1024 * $total_kb, total_items => 0 + $items,
            entries => \@entries,
        };
        print JSON::PP->new->utf8->canonical->encode($result), "\n";
    ' "$total_size_cleaned" "$files_cleaned" "$DRY_RUN_TOTAL_PARTIAL" \
        "$SYSTEM_CLEAN" "${MOLE_CLEAN_SIZING_TIMEOUTS:-0}" "${CLEAN_NATIVE_ACTIONS:-}" < "$ledger"
}
