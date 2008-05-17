#!/usr/bin/perl 
#
use warnings;
use strict;

use Prophet::Test tests => 12;

as_alice {
    run_ok( 'prophet', [qw(create --type Bug --status new --from alice )], "Created a record as alice" );
    run_output_matches( 'prophet', [qw(search --type Bug --regex .)], [qr/new/], " Found our record" );

    # update the record
    # show the record history
    # show the record
};

as_bob {
    run_ok( 'prophet', [qw(create --type Bug --status open --from bob )], "Created a record as bob" );
    run_output_matches( 'prophet', [qw(search --type Bug --regex .)], [qr/open/], " Found our record" );

    # update the record
    # show the record history
    # show the record

};

my $alice = Prophet::Replica->new( { url => repo_uri_for('alice') } );
my $bob   = Prophet::Replica->new( { url => repo_uri_for('bob') } );

is( $bob->db_uuid,
    $alice->db_uuid,
    "bob and alice's replicas need to have the same uuid for them to be able to sync without issues"
);

my $changesets = $bob->new_changesets_for($alice);

my $openbug = '';
as_bob {
    my ( $ret, $stdout, $stderr ) = run_script( 'prophet', [qw(search --type Bug --regex open)] );
    if ( $stdout =~ /^(.*?)\s/ ) {
        $openbug = $1;
    }
    is($bob->last_changeset_from_source($alice->uuid) => 0);

};

is_deeply(
    [ map { $_->as_hash } grep { !$_->is_empty}  @$changesets ],
    [ 
        {   'sequence_no'          => 3,
            'original_sequence_no' => 3,
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
    run_ok( 'prophet', [ 'merge', '--from', repo_uri_for('bob'), '--to', repo_uri_for('alice') ], "Sync ran ok!" );
    is($alice->last_changeset_from_source($bob->uuid) => $bob->latest_sequence_no);
};

my $last_id;

as_bob {
    run_ok( 'prophet', [qw(create --type Bug --status new --from bob )], "Created a record as bob" );
    my ( $ret, $stdout, $stderr ) = run_script( 'prophet', [qw(search --type Bug --regex new)] );
    if ( $stdout =~ /^(.*?)\s/ ) {
        $last_id = $1;
    }
};

$changesets = $bob->new_changesets_for($alice);

my @changes = map { $_->as_hash } grep {!$_->is_empty} @$changesets;

is_deeply(
    \@changes,
    [   {   'sequence_no'          => 4,
            'original_sequence_no' => 4,
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
                        }
                    },
                    'record_type' => 'Bug'
                }
            },
            'is_nullification' => undef,
        }
    ]
);

