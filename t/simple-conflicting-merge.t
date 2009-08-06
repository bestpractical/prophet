#!/usr/bin/perl 
#
use warnings;
use strict;

use Prophet::Test tests => 17;
use Test::Exception;

use_ok('Prophet::Replica');

as_alice {
    ok( run_command( 'init' ), 'replica init' );
    ok( run_command( qw(create --type Bug -- --status new --from alice ) ),
        'Created a record as alice' );
    my $output = run_command( qw(search --type Bug --regex .) );
    like( $output, qr/new/, 'Found our record' );
};

diag('Bob syncs from alice');

my $record_id;

as_bob {
    ok( run_command( 'clone', '--from', repo_uri_for('alice') ),
        'Sync ran ok!' );

    # check our local replicas
    my $out = run_command( qw(search --type Bug --regex .) );
    like( $out, qr/new/, "We have the one record from alice" );
    if ( $out =~ /'uuid': '(.*?)'/ ) {
        $record_id = $1;
    }

    ok( run_command(
            'update', '--type', 'Bug', '--uuid', $record_id,
            '--', '--status' => 'stalled',
        ),
        'update record',
    );
    $out = run_command(
        'show', '--batch', '--type', 'Bug', '--uuid', $record_id );
    my $alice_uuid = replica_uuid_for('alice');
    my $expected = qr/id: (\d+) \($record_id\)
creator: alice\@example.com
from: alice
original_replica: $alice_uuid
status: stalled/;
    like( $out, $expected, 'content is correct' );
};


my ($alice, $bob, $alice_app, $bob_app);
# This conflict, we can autoresolve
as_bob { $bob_app = Prophet::CLI->new()->app_handle; $bob = $bob_app->handle;};
as_alice { $alice_app = Prophet::CLI->new()->app_handle; $alice = $alice_app->handle};


as_alice {
    ok( run_command(
            'update', '--type', 'Bug', '--uuid',
            $record_id, '--', '--status' => 'stalled',
        ),
        'update record as alice',
    );
    my $output = run_command(
        'show', '--type', 'Bug', '--uuid', $record_id, '--batch',
    );
    my $alice_uuid = replica_uuid_for('alice');
    my $expected = qr/id: (\d+) \($record_id\)
creator: alice\@example.com
from: alice
original_replica: $alice_uuid
status: stalled/;
    like( $output, $expected, 'content is correct' );
};

# This conflict, we can autoresolve

diag("prebob");
as_bob {

    # XXX TODO: this should actually fail right now.
    # in perl code, we're going to run the merge (just as prophet-merge does)


    my $conflict_obj;
    lives_ok {
        $bob->import_changesets(
            from              => $alice,
            force             => 1,
            conflict_callback => sub {
                $conflict_obj = shift;
            }
        );
    };

    isa_ok( $conflict_obj, 'Prophet::Conflict' );

    my $conflicts = eval { serialize_conflict($conflict_obj)} ;

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
            creator              => undef,
            created              => undef,
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
    my @changesets =  @{ $bob->fetch_changesets( after => ( $bob->latest_sequence_no - 2) ) };

    # is the second most recent change:
    my $applied_null    = shift @changesets;
    my $applied_as_hash = $applied_null->as_hash;

    # these aren't available yet in the memory-version
    $applied_as_hash->{$_} = undef for qw(sequence_no source_uuid original_source_uuid original_sequence_no created);
    is_deeply( $applied_as_hash, $null_as_hash );


    # is the most recent change:
    my $from_alice = shift @changesets;

    my $from_alice_as_hash = $from_alice->as_hash;

    $from_alice_as_hash->{$_} = undef for qw(sequence_no source_uuid created);
    is_deeply(
        $from_alice_as_hash,
        {
            creator              => 'alice@example.com',
            created              => undef,
            is_nullification     => undef,
            is_resolution        => undef,
            source_uuid          => undef,
            sequence_no          => undef,
            original_sequence_no => $alice->latest_sequence_no,
            original_source_uuid => replica_uuid_for('alice'),
            changes              => {
                $record_id => {
                    record_type    => 'Bug',
                    change_type  => 'update_file',
                    prop_changes => { status => { old_value => 'new', new_value => 'stalled' } }
                },

                }

        },
        "yay. the last rev from alice synced right"
    );

};

diag("postbob");
