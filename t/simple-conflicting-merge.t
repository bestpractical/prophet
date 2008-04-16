#!/usr/bin/perl 
#
use warnings;
use strict;

use Prophet::Test tests => 17;
use Test::Exception;

as_alice {
    run_ok( 'prophet', [qw(create --type Bug --status new --from alice )], "Created a record as alice" );
    run_output_matches( 'prophet', [qw(search --type Bug --regex .)], [qr/new/], " Found our record" );
};

diag('Bob syncs from alice');

my $record_id;

as_bob {

    run_ok( 'prophet', [qw(create --type Dummy --ignore yes)], "Created a dummy record" );

    run_ok( 'prophet', [ 'merge',  '--to', repo_uri_for('bob'), '--from', repo_uri_for('alice') ], "Sync ran ok!" );

    # check our local replicas
    my ( $ret, $out, $err ) = run_script( 'prophet', [qw(search --type Bug --regex .)] );
    like( $out, qr/new/, "We have the one record from alice" );
    if ( $out =~ /^(.*?)\s./ ) {
        $record_id = $1;
    }

    run_ok( 'prophet', [ 'update', '--type', 'Bug', '--uuid', $record_id, '--status' => 'stalled' ] );
    run_output_matches(
        'prophet',
        [ 'show','--type',            'Bug',             '--uuid', $record_id ],
        [ 'id: ' . $record_id, 'status: stalled', 'from: alice' ],
        'content is correct'
    );
};

as_alice {
    run_ok( 'prophet', [ 'update', '--type', 'Bug', '--uuid', $record_id, '--status' => 'stalled' ] );
    run_output_matches(
        'prophet',
        ['show', '--type',            'Bug',             '--uuid', $record_id ],
        [ 'id: ' . $record_id, 'status: stalled', 'from: alice' ],
        'content is correct'
    );

};

# This conflict, we can autoresolve

as_bob {

    # XXX TODO: this should actually fail right now.
    # in perl code, we're going to run the merge (just as prophet-merge does)

    use_ok('Prophet::Replica');

    my $source = Prophet::Replica->new( { url => repo_uri_for('alice') } );
    my $target = Prophet::Replica->new( { url => repo_uri_for('bob') } );

    my $conflict_obj;

    my $repo = repo_uri_for('bob');

    lives_ok {
        $target->import_changesets(
            from              => $source,
            conflict_callback => sub {
                $conflict_obj = shift;
            }
        );
    };

    isa_ok( $conflict_obj, 'Prophet::Conflict' );

    my $conflicts = serialize_conflict($conflict_obj);

    is_deeply(
        $conflicts,
        {   meta    => { original_source_uuid => replica_uuid_for('alice') },
            records => {
                $record_id => {
                    change_type => 'update_file',
                    props       => {
                        status => {
                            source_new => 'stalled',
                            source_old => 'new',
                            target_old => 'stalled'
                        }
                    }
                }
            }
        }
    );

    # Check to see if the nullification changeset worked out ok
    my $nullification = $conflict_obj->nullification_changeset;
    isa_ok( $nullification, "Prophet::ChangeSet" );

    my $null_as_hash = serialize_changeset($nullification);

    is_deeply(
        $null_as_hash,
        {

            is_empty             => 0,
            is_nullification     => 1,
            is_resolution        => undef,
            original_sequence_no => undef,
            original_source_uuid => undef,
            sequence_no          => undef,
            source_uuid          => undef,
            changes              => {
                $record_id => {
                    change_type  => 'update_file',
                    record_type    => 'Bug',
                    prop_changes => { status => { old_value => 'stalled', new_value => 'new' } }
                    }

            }
        }
    );

    # replay the last two changesets for bob's replica
    my @changesets = fetch_newest_changesets(2);

    # is the second most recent change:
    my $applied_null    = shift @changesets;
    my $applied_as_hash = $applied_null->as_hash;

    # these aren't available yet in the memory-version
    $applied_as_hash->{$_} = undef for qw(sequence_no source_uuid original_source_uuid original_sequence_no);
    is_deeply( $applied_as_hash, $null_as_hash );

    # is the most recent change:
    my $from_alice = shift @changesets;

    my $from_alice_as_hash = $from_alice->as_hash;

    $from_alice_as_hash->{$_} = undef for qw(sequence_no source_uuid);
    is_deeply(
        $from_alice_as_hash,
        {   is_empty             => 0,
            is_nullification     => undef,
            is_resolution        => undef,
            source_uuid          => undef,
            sequence_no          => undef,
            original_sequence_no => as_alice { replica_last_rev() },
            original_source_uuid => replica_uuid_for('alice'),
            changes              => {
                $record_id => {
                    record_type    => 'Bug',
                    change_type  => 'update_file',
                    prop_changes => { status => { old_value => 'new', new_value => 'stalled' } }
                },

                replica_uuid_for('alice') => {
                    change_type  => 'update_file',
                    record_type    => '_merge_tickets',
                    prop_changes => {
                        'last-changeset' => {
                            old_value => as_alice { replica_last_rev() - 1 },
                            new_value => as_alice { replica_last_rev() }
                        }
                        }

                    }

                }

        },
        "yay. the last rev from alice synced right"
    );

};

