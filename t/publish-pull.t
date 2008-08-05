#!/usr/bin/perl
use warnings;
use strict;
use Prophet::Test tests => 22;
use Test::Exception;
use File::Temp 'tempdir';
use Path::Class;
use Params::Validate;

my $alice_published = tempdir(CLEANUP => 1);

as_alice {
    run_ok( 'prophet', [qw(create --type Bug -- --status new --from alice )], "Created a record as alice" );
    run_output_matches( 'prophet', [qw(search --type Bug --regex .)], [qr/new/], " Found our record" );

    run_ok( 'prophet', [qw(publish --to), $alice_published] );
};

my $alice_uuid = database_uuid_for('alice');
my $path = dir($alice_published)->file($alice_uuid);

as_bob {
    run_ok( 'prophet', ['pull', '--from', "file:$path", '--force'] );
    run_output_matches( 'prophet', [qw(search --type Bug --regex .)], [qr/new/], " Found our record" );
};

as_alice {
    run_ok( 'prophet', [qw(create --type Pullall -- --status new --from alice )], "Created another record as alice" );
    run_ok( 'prophet', [qw(publish --to), $alice_published] );
};

as_bob {
    run_ok( 'prophet', ['pull', '--all', '--force'] );
    run_output_matches( 'prophet', [qw(search --type Pullall --regex .)], [qr/new/], " Found our record" );
};

# see if uuid intuition works
# e.g. I hand you a url, http://sartak.org/misc/sd, and Prophet figures out
# that you really want http://sartak.org/misc/sd/DATABASE-UUID
as_charlie {
    my $cli  = Prophet::CLI->new();
    $cli->app_handle->handle->set_db_uuid($alice_uuid);

    run_ok( 'prophet', ['pull', '--from', "file:$alice_published", '--force'] );
    run_output_matches( 'prophet', [qw(search --type Bug --regex .)], [qr/new/], "publish database uuid intuition works" );
};

as_david {
    run_ok( 'prophet', ['pull', '--from', "file:$path"] );
};

is(database_uuid_for('alice'), database_uuid_for('david'), "pull propagated the database uuid properly");
isnt(replica_uuid_for('alice'), replica_uuid_for('david'), "pull created a new replica uuid");

for my $user ('alice', 'bob', 'charlie', 'david') {
    my $replica = Prophet::Replica->new({ url => repo_uri_for($user) });
    my $changesets = $replica->fetch_changesets(after => 0);

    diag "Verifying $user\'s first changeset";
    changeset_ok(
        changeset   => $changesets->[0],
        user        => $user,
        record_type => 'Bug',
        sequence_no => 1,
        merge       => $user ne 'alice',
    );

    diag "Verifying $user\'s second changeset";
    changeset_ok(
        changeset   => $changesets->[1],
        user        => $user,
        record_type => 'Pullall',
        sequence_no => 2,
        merge       => $user ne 'alice',
    );
}

sub changeset_ok {
    local $Test::Builder::Level = $Test::Builder::Level + 1;

    my %args = validate(@_, {
        changeset   => 1,
        user        => 1,
        sequence_no => 1,
        record_type => 1,
        merge       => 1,
    });

    my $changeset = $args{changeset};

    is_deeply($changeset, bless {
        creator              => 'alice',
        created              => $changeset->created,
        is_resolution        => undef,
        is_nullification     => undef,
        sequence_no          => $args{sequence_no},,
        source_uuid          => replica_uuid_for($args{user}),
        original_sequence_no => $args{sequence_no},
        original_source_uuid => replica_uuid_for('alice'),
        changes              => [
            bless({
                change_type  => 'add_file',
                record_type  => $args{record_type},
                record_uuid  => $changeset->changes->[0]->record_uuid,
                prop_changes => [
                    bless({
                        name      => 'status',
                        old_value => undef,
                        new_value => 'new',
                    }, 'Prophet::PropChange'),
                    bless {
                        name      => 'from',
                        old_value => undef,
                        new_value => 'alice',
                    }, 'Prophet::PropChange',
                ],
            }, 'Prophet::Change'),

            # need to account for the merge ticket except in the original
            # replica
            $args{merge}
            ? $changeset->changes->[1]
            : ()
        ],
    }, 'Prophet::ChangeSet');
}

