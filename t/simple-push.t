#!/usr/bin/perl 
#
use warnings;
use strict;

use Prophet::Test tests => 14;

as_alice {
    run_ok( 'prophet', [qw(create --type Bug -- --status new --from alice )], "Created a record as alice" );
    run_output_matches( 'prophet', [qw(search --type Bug --regex .)], [qr/new/], " Found our record" );

    # update the record
    # show the record history
    # show the record
};

as_bob {
    run_ok( 'prophet', [qw(create --type Bug -- --status open --from bob )], "Created a record as bob" );
    run_output_matches( 'prophet', [qw(search --type Bug --regex .)], [qr/open/], " Found our record" );

    # update the record
    # show the record history
    # show the record

};

my $alice = Prophet::Replica->new( { url => repo_uri_for('alice') } );
my $bob   = Prophet::Replica->new( { url => repo_uri_for('bob') } );
TODO: {
    local $TODO = "Eventually, we'll want to ensure that you can't merge databases which aren't already replicas";
is( $bob->db_uuid,
    $alice->db_uuid,
    "bob and alice's replicas need to have the same uuid for them to be able to sync without issues"
);
};


my $openbug = '';
as_bob {
    my ( $ret, $stdout, $stderr ) = run_script( 'prophet', [qw(search --type Bug --regex open)] );
    if ( $stdout =~ /^(.*?)\s/ ) {
        $openbug = $1;
    }
    is($bob->last_changeset_from_source($alice->uuid) => 0);

};

my $changesets =   [ map { $_->as_hash } grep { $_->has_changes }  @{$bob->new_changesets_for($alice, force => 1)}];
my $seq = delete $changesets->[0]->{'sequence_no'};
my $orig_seq = delete $changesets->[0]->{'original_sequence_no'};
is($seq, $orig_seq);


is_deeply(
   $changesets,
    [ 
        {   #'sequence_no'          => 3,
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
                            'new_value' => 'open',
                            'old_value' => undef
                        },
                        'creator' => {
                            'new_value' => 'bob@' . replica_uuid_for('bob'),
                            'old_value' => undef
                        }
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
    is($alice->last_changeset_from_source($bob->uuid) => 0);
    run_ok( 'prophet', [ 'merge', '--from', repo_uri_for('bob'), '--to', repo_uri_for('alice'), '--force' ], "Sync ran ok!" );
    is($alice->last_changeset_from_source($bob->uuid) => $bob->latest_sequence_no);
};

my $last_id;

as_bob {
    run_ok( 'prophet', [qw(create --type Bug -- --status new --from bob )], "Created a record as bob" );
    my ( $ret, $stdout, $stderr ) = run_script( 'prophet', [qw(search --type Bug --regex new)] );
    if ( $stdout =~ /^(.*?)\s/ ) {
        $last_id = $1;
    }
};

$changesets = $bob->new_changesets_for($alice, force => 1);

my @changes = map { $_->as_hash } grep { $_->has_changes } @$changesets;

is( delete $changes[0]->{'sequence_no'}, delete $changes[0]->{'original_sequence_no'});

is_deeply(
    \@changes,
    [   {  
        
        #     'sequence_no'          => 4,  # the number varies based on replica type
        #    'original_sequence_no' => 4,
            'creator'              => 'bob',
            'created'              => $changes[0]->{created},
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
                            'new_value' => 'new',
                            'old_value' => undef
                        },
                        'creator' => {
                            'new_value' => 'bob@' . replica_uuid_for('bob'),
                            'old_value' => undef,
                        },
                    },
                    'record_type' => 'Bug'
                }
            },
            'is_nullification' => undef,
        }
    ]
);

