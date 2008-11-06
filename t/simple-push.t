#!/usr/bin/perl 
#
use warnings;
use strict;

use Prophet::Test tests => 16;

as_alice {
    run_ok( 'prophet', [qw(init)]);
    run_ok( 'prophet', [qw(create --type Bug -- --status new --from alice )], "Created a record as alice" );
    run_output_matches( 'prophet', [qw(search --type Bug --regex .)], [qr/new/], " Found our record" );

    # update the record
    # show the record history
    # show the record
};

diag(repo_uri_for('alice'));
as_bob {
    run_ok( 'prophet', [qw(clone --from), repo_uri_for('alice')]);
    run_ok( 'prophet', [qw(create --type Bug -- --status open --from bob )], "Created a record as bob" );
    run_output_matches( 'prophet', [qw(search --type Bug --regex .)], [qr/open/, qr/new/], " Found our record" );

    # update the record
    # show the record history
    # show the record

};

my $alice; 
my $bob;

as_alice { $alice = Prophet::CLI->new; };
as_bob { $bob = Prophet::CLI->new; };


is( $bob->app_handle->handle->db_uuid,
    $alice->app_handle->handle->db_uuid,
    "bob and alice's replicas need to have the same uuid for them to be able to sync without issues"
);


my $openbug = '';
as_bob {
    my ( $ret, $stdout, $stderr ) = run_script( 'prophet', [qw(search --type Bug --regex open)] );
    if ( $stdout =~ /^(.*?)\s/ ) {
        $openbug = $1;
    }
    is($bob->app_handle->handle->last_changeset_from_source($alice->app_handle->handle->uuid) => $alice->app_handle->handle->latest_sequence_no);

};

my $changesets;
    $bob->app_handle->handle->traverse_new_changesets( for => $alice->app_handle->handle, force => 1,
            callback => sub {
                my $cs = shift;
                return unless $cs->has_changes,
                push @{$changesets}, $cs->as_hash;
            }
        
        
    );


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
            'changes'              => [
                {
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
                            'new_value' => 'bob',
                            'old_value' => undef
                        },
                        'original_replica' => {
                            'new_value' => replica_uuid_for('bob'),
                            'old_value' => undef
                        },
                    },
                    'record_uuid' => $openbug,
                    'record_type' => 'Bug'
                }
            ],
            'is_nullification' => undef,
        }
    ]
);

# Alice syncs

as_alice {

    # sync from bob
    diag('Alice syncs from bob');
    is($alice->app_handle->handle->last_changeset_from_source($bob->app_handle->handle->uuid) => 0);
    run_ok( 'prophet', [ 'pull', '--from', repo_uri_for('bob'), '--to' ], "Sync ran ok!" );
    is($alice->app_handle->handle->last_changeset_from_source($bob->app_handle->handle->uuid) => $bob->app_handle->handle->latest_sequence_no);
};

my $last_id;

as_bob {
    run_ok( 'prophet', [qw(create --type Bug -- --status new --from bob )], "Created a record as bob" );
    my ( $ret, $stdout, $stderr ) = run_script( 'prophet', [qw(search --type Bug --regex new)] );
    if ( $stdout =~ /^(.*?)\s/ ) {
        $last_id = $1;
    }
};

my $new_changesets;
    $bob->handle->traverse_new_changesets( for => $alice->app_handle->handle, force => 1,
            callback => sub {
                my $cs = shift;
                return unless $cs->has_changes,
                push @{$new_changesets}, $cs->as_hash;
            }
        
        
    );


is( delete $new_changesets->[0]->{'sequence_no'}, delete $new_changesets->[0]->{'original_sequence_no'});

is_deeply(
    $new_changesets,
    [   {  
        
        #     'sequence_no'          => 4,  # the number varies based on replica type
        #    'original_sequence_no' => 4,
            'creator'              => 'bob',
            'created'              => $new_changesets->[0]->{created},
            'original_source_uuid' => replica_uuid_for('bob'),
            'is_resolution'        => undef,
            'source_uuid'          => replica_uuid_for('bob'),
            'changes'              => [
                {
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
                            'new_value' => 'bob',
                            'old_value' => undef,
                        },
                        'original_replica' => {
                            'new_value' => replica_uuid_for('bob'),
                            'old_value' => undef,
                        },
                    },
                    'record_uuid' => $last_id,
                    'record_type' => 'Bug',
                }
            ],
            'is_nullification' => undef,
        }
    ]
);

