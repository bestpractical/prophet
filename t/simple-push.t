#!/usr/bin/perl 
#
use warnings;
use strict;

use Prophet::Test tests => 17;

as_alice {
    ok( run_command( qw(init) ), 'replica init' );
    ok( run_command( qw(create --type Bug -- --status new-alice --from alice )),
        'Created a record as alice'
    );
    my $output = run_command( qw(search --type Bug --regex .) );
    like( $output, qr/new/, 'Found our record' );

    # update the record
    # show the record history
    # show the record
};

diag( repo_uri_for('alice') );
as_bob {
    ok( run_command( qw(clone --from), repo_uri_for('alice') ),
        'clone from alice' );
    ok( run_command( qw(create --type Bug -- --status open-bob --from bob ) ),
        'Created a record as bob' );
    my $output = run_command( qw(search --type Bug --regex new-alice) );
    like( $output, qr/new-alice/, 'Found our record' );

    $output = run_command( qw(search --type Bug --regex open-bob) );
    like( $output, qr/open-bob/, 'Found our record' );

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
    my $stdout = run_command( qw(search --type Bug --regex open-bob) );
    if ( $stdout =~ /^'uuid': '(.*?)'\s/ ) {
        $openbug = $1;
    }
    diag(
        "As bob, the last changeset I've seen from alice is "
            . $bob->last_changeset_from_source(
            $alice->uuid
            )
    );
    diag("As alice, my latest sequence # is " .$alice->latest_sequence_no);
    is( $bob->last_changeset_from_source( $alice->uuid ) =>
            $alice->latest_sequence_no );

};

my $changesets;
$bob->traverse_changesets(
    after    => $alice->last_changeset_from_source($bob->uuid),
    callback => sub {
        my %args = (@_);
        return unless $alice->should_accept_changeset( $args{changeset});
        push @{$changesets}, $args{changeset}->as_hash;
    }
);

my $seq      = delete $changesets->[0]->{'sequence_no'};
my $orig_seq = delete $changesets->[0]->{'original_sequence_no'};
is( $seq, $orig_seq );
my $cs_data =    [   {    #'sequence_no'          => 3,
             #'original_sequence_no' => 3, # the number is different on different replica types
            'creator'              => 'bob@example.com',
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
                            'new_value' => 'bob@example.com',
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
    ];


is_deeply( $changesets,$cs_data);


# Alice syncs

as_alice {

    # sync from bob
    diag('Alice syncs from bob');
    is( $alice->last_changeset_from_source( $bob->uuid ) => -1 );
    ok( run_command( 'pull', '--from', repo_uri_for('bob') ),
        'Sync ran ok!' );
    is( $alice->last_changeset_from_source( $bob->uuid ) =>
            $bob->latest_sequence_no );
};

my $last_id;

as_bob {
    ok( run_command( qw(create --type Bug -- --status new2-bob --from bob ) ),
        'Created a record as bob');
    my $stdout = run_command( qw(search --type Bug --regex new2) );
    if ( $stdout =~ /^'uuid': '(.*?)'\s/ ) {
        $last_id = $1;
    }
};

my $new_changesets;
$bob->traverse_changesets(
    after    => $alice->last_changeset_from_source($bob->uuid),
    callback => sub {
        my %args = (@_);
        return unless $args{changeset}->has_changes, push @{$new_changesets}, $args{changeset}->as_hash;
        }

);

is( delete $new_changesets->[0]->{'sequence_no'},
    delete $new_changesets->[0]->{'original_sequence_no'}
);



 our $expected =   [   {

   #     'sequence_no'          => 4,  # the number varies based on replica type
   #    'original_sequence_no' => 4,
            'creator'              => 'bob@example.com',
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
                            'new_value' => 'bob@example.com',
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
