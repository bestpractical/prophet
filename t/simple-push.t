#!/usr/bin/perl 
#
use warnings;
use strict;

use Prophet::Test tests => 16;

as_alice {
    run_ok( 'prophet', [qw(init)] );
    run_ok(
        'prophet',
        [qw(create --type Bug -- --status new-alice --from alice )],
        "Created a record as alice"
    );
    run_output_matches(
        'prophet', [qw(search --type Bug --regex .)],
        [qr/new/], " Found our record"
    );

    # update the record
    # show the record history
    # show the record
};

diag( repo_uri_for('alice') );
as_bob {
    run_ok( 'prophet', [ qw(clone --from), repo_uri_for('alice') ] );
    run_ok(
        'prophet',
        [qw(create --type Bug -- --status open-bob --from bob )],
        "Created a record as bob"
    );
    run_output_matches(
        'prophet',
        [qw(search --type Bug --regex .)],
        [ qr/open-bob/, qr/new-alice/ ],
        " Found our record"
    );

    # update the record
    # show the record history
    # show the record

};

my ($alice, $alice_app);
my ($bob, $bob_app);

as_alice { $alice_app = Prophet::CLI->new->app_handle; $alice= $alice_app->handle };
as_bob { $bob_app = Prophet::CLI->new->app_handle; $bob = $bob_app->handle };

is( $bob->db_uuid, $alice->db_uuid,
    "bob and alice's replicas need to have the same uuid for them to be able to sync without issues"
);

my $openbug = '';
as_bob {
    my ( $ret, $stdout, $stderr )
        = run_script( 'prophet', [qw(search --type Bug --regex open-bob)] );
    if ( $stdout =~ /^(.*?)\s/ ) {
        $openbug = $1;
    }
    diag(
        "As bob, the last changeset I've seen from alice is "
            . $bob->last_changeset_from_source(
            $alice->uuid
            )
    );
    is( $bob->last_changeset_from_source( $alice->uuid ) =>
            $alice->latest_sequence_no );

};

my $changesets;
$bob->traverse_new_changesets(
    for      => $alice,
    force    => 1,
    callback => sub {
        my $cs = shift;
        return unless $cs->has_changes, push @{$changesets}, $cs->as_hash;
    }
);

my $seq      = delete $changesets->[0]->{'sequence_no'};
my $orig_seq = delete $changesets->[0]->{'original_sequence_no'};
is( $seq, $orig_seq );

is_deeply(
    $changesets,
    [   {    #'sequence_no'          => 3,
             #'original_sequence_no' => 3, # the number is different on different replica types
            'creator'              => 'bob',
            'created'              => $changesets->[0]->{created},
            'original_source_uuid' => replica_uuid_for('bob'),
            'is_resolution'        => undef,
            'source_uuid'          => replica_uuid_for('bob'),
            'changes'              => {
                $openbug => {
                    'change_type'  => 'add_file',
                    'prop_changes' => {
                        'from' => {
                            'new_value' => 'bob',
                            'old_value' => undef
                        },
                        'status' => {
                            'new_value' => 'open-bob',
                            'old_value' => undef
                        },
                        'creator' => {
                            'new_value' => 'bob',
                            'old_value' => undef
                        },
                        'original_replica' => {
                            'new_value' => replica_uuid_for('bob'),
                            'old_value' => undef
                        },
                    },
                    'record_type' => 'Bug'
                }
            },
            'is_nullification' => undef,
        }
    ]
);

# Alice syncs

as_alice {

    # sync from bob
    diag('Alice syncs from bob');
    is( $alice->last_changeset_from_source( $bob->uuid ) => 0 );
    run_ok( 'prophet', [ 'pull', '--from', repo_uri_for('bob') ],
        "Sync ran ok!" );
    is( $alice->last_changeset_from_source( $bob->uuid ) =>
            $bob->latest_sequence_no );
};

my $last_id;

as_bob {
    run_ok(
        'prophet',
        [qw(create --type Bug -- --status new2-bob --from bob )],
        "Created a record as bob"
    );
    my ( $ret, $stdout, $stderr )
        = run_script( 'prophet', [qw(search --type Bug --regex new2)] );
    if ( $stdout =~ /^(.*?)\s/ ) {
        $last_id = $1;
    }
};

my $new_changesets;
$bob->traverse_new_changesets(
    for      => $alice,
    force    => 1,
    callback => sub {
        my $cs = shift;
        return unless $cs->has_changes, push @{$new_changesets}, $cs->as_hash;
        }

);

is( delete $new_changesets->[0]->{'sequence_no'},
    delete $new_changesets->[0]->{'original_sequence_no'}
);



 our $expected =   [   {

   #     'sequence_no'          => 4,  # the number varies based on replica type
   #    'original_sequence_no' => 4,
            'creator'              => 'bob',
            'created'              => $new_changesets->[0]->{created},
            'original_source_uuid' => replica_uuid_for('bob'),
            'is_resolution'        => undef,
            'source_uuid'          => replica_uuid_for('bob'),
            'changes'              => {
                $last_id => {
                    'change_type'  => 'add_file',
                    'prop_changes' => {
                        'from' => {
                            'new_value' => 'bob',
                            'old_value' => undef
                        },
                        'status' => {
                            'new_value' => 'new2-bob',
                            'old_value' => undef
                        },
                        'creator' => {
                            'new_value' => 'bob',
                            'old_value' => undef,
                        },
                        'original_replica' => {
                            'new_value' => replica_uuid_for('bob'),
                            'old_value' => undef,
                        },
                    },
                    'record_type' => 'Bug'
                }
            },
            'is_nullification' => undef,
        }
    ];




is_deeply(
    $new_changesets,
    $expected
);
