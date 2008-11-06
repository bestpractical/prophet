#!/usr/bin/perl

use warnings;
use strict;
use Test::Exception;

use Prophet::Test tests => 21;

as_alice {
    run_command(qw(init));
    like(run_command(qw(create --type Bug -- --status new --from alice)), qr/Created Bug/, "Created a record as alice");
    like(run_command(qw(search --type Bug --regex .)), qr/new/, "Found our record");
};

diag('Bob syncs from alice');

my $record_id;

as_bob {

    run_command(qw(init));
    like(run_command(qw(create --type Dummy -- --ignore yes)), qr/Created Dummy/);
    like(run_command('merge', '--to', repo_uri_for('bob'), '--from', repo_uri_for('alice'), '--force'), qr/Merged one changeset/, "Sync ran ok!");

    # check our local replicas
    my $out = run_command(qw(search --type Bug --regex .));
    like($out, qr/new/, "We have the one record from alice" );
    if ( $out =~ /^(.*?)\s./ ) {
        $record_id = $1;
    }

    like(run_command( 'update', '--type', 'Bug', '--uuid', $record_id, '--', '--status' => 'stalled'), qr/Bug .* updated/);

    run_output_matches(
        'prophet',
        [ 'show', '--type', 'Bug', '--uuid', $record_id, '--batch' ],
        [
        qr/id: (\d+) \($record_id\)/,
          'creator: alice',
          'from: alice',
          'original_replica: ' . replica_uuid_for('alice'),
          'status: stalled',
        ],
        'content is correct'
    );
};

as_alice {
    like(run_command('update', '--type', 'Bug', '--uuid', $record_id, '--', '--status' => 'open' ), qr/Bug .* updated/);

    run_output_matches(
        'prophet',
        [ 'show', '--type', 'Bug', '--uuid', $record_id, '--batch' ],
        [
            qr/id: (\d+) \($record_id\)/,
              'creator: alice',
              'from: alice',
              'original_replica: ' . replica_uuid_for('alice'),
              'status: open',
        ],
        'content is correct'
    );

};

# This conflict, we can autoresolve

as_bob {
    use_ok('Prophet::Replica');
    my $source = Prophet::Replica->new( { url => repo_uri_for('alice') } );
    my $target = Prophet::Replica->new( { url => repo_uri_for('bob') } );

    my $conflict_obj;

    throws_ok {
        $target->import_changesets( from => $source, force => 1);
    }
    qr/not resolved/;

    throws_ok {
        $target->import_changesets(
            from     => $source,
            resolver => sub { die "my way of death\n" },
            force    => 1,
        );
    }
    qr/my way of death/, 'our resolver is actually called';

    ok_added_revisions(
        sub {

            $target->import_changesets(
                from           => $source,
                resolver_class => 'Prophet::Resolver::AlwaysTarget',
                force          => 1,
            );
        },
        3,
        '3 revisions since the merge'
    );

    my @changesets = fetch_newest_changesets(3);

    my $resolution = $changesets[2];
    ok( $resolution->is_resolution, 'marked as resolution' );
    my $repo = repo_uri_for('bob');

    #    diag `svn log -v $repo`;

    check_bob_final_state_ok(@changesets);
};
as_alice {
    my $source = Prophet::Replica->new( { url => repo_uri_for('bob') } );
    my $target = Prophet::Replica->new( { url => repo_uri_for('alice') } );
    throws_ok {
        $target->import_changesets( from => $source, force => 1 );
    }
    qr/not resolved/;

    $target->import_resolutions_from_remote_replica( from => $source, force => 1 );

    $target->import_changesets(
        from  => $source,
        resdb => $target->resolution_db_handle,
        force => 1,
    );

    lives_and {
        ok_added_revisions(
            sub {
                $target->import_changesets( from => $source, force => 1 );
            },
            0,
            'no more changes to sync'
        );

    };
};

as_bob {
    my $source = Prophet::Replica->new( { url => repo_uri_for('alice') } );
    my $target = Prophet::Replica->new( { url => repo_uri_for('bob') } );

    lives_and {
        ok_added_revisions(
            sub {
                $target->import_changesets( from => $source, force => 1 );
            },
            0,
            'no more changes to sync'
        );

    };

    check_bob_final_state_ok( fetch_newest_changesets(3) );

};

our $ALICE_LAST_REV_CACHE;

sub check_bob_final_state_ok {
    my (@changesets) = (@_);

    $ALICE_LAST_REV_CACHE ||= as_alice { replica_last_rev() };

    my @hashes = map { $_->as_hash } @changesets;
    is_deeply(
        \@hashes,
        [   {   changes => [
                    {
                        change_type  => 'update_file',
                        record_uuid  => $record_id,
                        record_type  => 'Bug',
                        prop_changes => {
                            status => {
                                old_value => 'stalled',
                                new_value => 'new'
                            }
                        }
                    }
                ],
                creator              => undef,
                created              => $changesets[0]->created,
                is_nullification     => 1,
                is_resolution        => undef,
                sequence_no          => ( replica_last_rev() - 2 ),
                original_sequence_no => ( replica_last_rev() - 2 ),
                source_uuid          => replica_uuid(),
                original_source_uuid => replica_uuid(),
            },
            {
                creator              => 'alice',
                created              => $changesets[1]->created,
                is_nullification     => undef,
                is_resolution        => undef,
                sequence_no          => ( replica_last_rev() - 1 ),
                original_sequence_no => $ALICE_LAST_REV_CACHE,
                source_uuid          => replica_uuid(),
                original_source_uuid => as_alice { replica_uuid() },
                changes              => [
                    {
                        record_uuid  => $record_id,
                        record_type  => 'Bug',
                        change_type  => 'update_file',
                        prop_changes => {
                            status => { old_value => 'new', new_value => 'open' }
                        },
                    },
                    {
                        record_uuid  => as_alice{ replica_uuid() },
                        record_type  => '_merge_tickets',
                        change_type  => 'update_file',
                        prop_changes => {
                            'last-changeset' => {
                                old_value => $ALICE_LAST_REV_CACHE - 1,
                                new_value => $ALICE_LAST_REV_CACHE
                            }
                        }
                    }
                ],
            },

            {
                creator              => 'bob',
                created              => $changesets[2]->created,
                is_nullification     => undef,
                is_resolution        => 1,
                sequence_no          => replica_last_rev(),
                original_sequence_no => replica_last_rev(),
                source_uuid          => replica_uuid(),
                original_source_uuid => replica_uuid(),
                changes              => [
                    {
                        record_uuid  => $record_id,
                        record_type  => 'Bug',
                        change_type  => 'update_file',
                        prop_changes => {
                            status => { old_value => 'open', new_value => 'stalled' }
                        },
                    }
                ]
            }
        ],
        "Bob's final state is as we expect"
    );
}
