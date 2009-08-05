#!/usr/bin/perl
use warnings;
use strict;
use Prophet::Test tests => 33;
use File::Temp qw(tempdir tempfile);
use Params::Validate;
use Prophet::Util;

my ($bug_uuid, $pullall_uuid);

my $alice_published = tempdir(CLEANUP => ! $ENV{PROPHET_DEBUG});

(undef, my $alice_config) = tempfile( CLEANUP => ! $ENV{PROPHET_DEBUG} );
(undef, my $bob_config) = tempfile( CLEANUP => ! $ENV{PROPHET_DEBUG} );
diag "Alice's config file is located at $alice_config";
diag "Bob's config file is located at $bob_config";

as_alice {
    $ENV{PROPHET_APP_CONFIG} = $alice_config;
    ok( run_command( qw(init) ), 'replica init' );

    # check that new config section has been created with uuid variable
    my $config_contents = Prophet::Util->slurp($ENV{PROPHET_APP_CONFIG});
    like($config_contents, qr/
\[core\]
	config-format-version = \d+
\[replica ".*?"\]
	uuid = $Prophet::CLIContext::ID_REGEX
/, 'replica section created in config file after init');

    my $output
        = run_command( qw(create --type Bug -- --status new --from alice ) );
    my $expected = qr/Created Bug \d+ \((\S+)\)(?{ $bug_uuid = $1 })/;
    like( $output, $expected, 'Created a Bug record as alice' );

    ok($bug_uuid, "got a uuid for the Bug record");

    $output
        = run_command( qw(search --type Bug --regex .) );
    $expected = qr/new/;
    like( $output, $expected, 'Found our record' );

    ok( run_command( qw(publish --to), $alice_published ),
        'publish --to'
    );

    # check that publish-url config key has been created correctly
    $config_contents = Prophet::Util->slurp($ENV{PROPHET_APP_CONFIG});
    like($config_contents, qr/
\[core\]
	config-format-version = \d+
\[replica "(.*?)"\]
	uuid = $Prophet::CLIContext::ID_REGEX
	publish-url = \Q$alice_published\E
/, 'publish-url variable created correctly in config');
    $config_contents =~ /\[replica "(.*?)"\]/;
    my $replica_name = $1;

    # change name in config
    my $new_config_contents = $config_contents;
    $new_config_contents =~ s/\Q$replica_name\E/new-name/;
    Prophet::Util->write_file(
        file => $ENV{PROPHET_APP_CONFIG},
        content => $new_config_contents,
    );

    # publish again to a different location
    my $new_published = tempdir( CLEANUP => ! $ENV{PROPHET_DEBUG} );
    ok( run_command( qw(publish --to), $new_published ),
        'publish again to different location',
    );
    # make sure the subsection name was changed and the publish-url
    # was updated, rather than a new section being created
    $config_contents = Prophet::Util->slurp($ENV{PROPHET_APP_CONFIG});
    like($config_contents, qr/
\[core\]
	config-format-version = \d+
\[replica "new-name"\]
	uuid = $Prophet::CLIContext::ID_REGEX
	publish-url = \Q$new_published\E
/, 'publish-url variable created correctly in config');

    # check to make sure that publish doesn't fall back to using
    # url, since that would never make sense
    $new_config_contents =~ /uuid = ($Prophet::CLIContext::ID_REGEX)/;
    my $uuid = $1;
    $new_published = tempdir( CLEANUP => ! $ENV{PROPHET_DEBUG} );
    my $bogus_name = tempdir( CLEANUP => ! $ENV{PROPHET_DEBUG} );
    Prophet::Util->write_file(
        file => $ENV{PROPHET_APP_CONFIG},
        content => <<EOF,
[replica "$bogus_name"]
	uuid = $uuid
	url = $new_published
EOF
    );
    # diag "publishing to $new_published";
    # diag "bogus name is $bogus_name";
    ok( run_command( qw(publish --to), $bogus_name ),
        'publish to bogus name',
    );
    ok( ! -f File::Spec->catfile( $new_published, 'config' )
        && -f File::Spec->catfile( $bogus_name, 'replica-uuid' ),
        'did not fall back to url variable' );
};

my $path =$alice_published;

as_bob {
    $ENV{PROPHET_APP_CONFIG} = $bob_config;
    ok( run_command( 'clone', '--from', "file://$path" ),
        'clone as bob',
    );
    my $config_contents = Prophet::Util->slurp($ENV{PROPHET_APP_CONFIG});
    like($config_contents, qr|
\[core\]
	config-format-version = \d+
\[replica "file://\Q$path\E"\]
	url = file://\Q$path\E
	uuid = $Prophet::CLIContext::ID_REGEX
|, 'replica section created in config file after clone');

    my $output = run_command( qw(search --type Bug --regex .));
    my $expected = qr/new/;
    like( $output, $expected, 'Found our record' );
};

as_alice {
    $ENV{PROPHET_APP_CONFIG} = $alice_config;
    my $output
        = run_command( qw(create --type Pullall -- --status new --from alice ));
    my $expected = qr/Created Pullall \d+ \((\S+)\)(?{ $pullall_uuid = $1 })/;
    like( $output, $expected, 'Created a Pullall record as alice' );

    ok($pullall_uuid, "got a uuid $pullall_uuid for the Pullall record");

    ok( run_command( qw(publish --to), $alice_published ),
        'publish as alice',
    );
};

as_bob {
    $ENV{PROPHET_APP_CONFIG} = $bob_config;

    # change name in config
    my $config_contents = Prophet::Util->slurp($ENV{PROPHET_APP_CONFIG});
    $config_contents =~ /\[replica "(.*?)"\]/;
    my $replica_name = $1;
    my $new_config_contents = $config_contents;
    $new_config_contents =~ s/\Q$replica_name\E/new-name/;
    Prophet::Util->write_file(
        file => $ENV{PROPHET_APP_CONFIG},
        content => $new_config_contents,
    );
    ok( run_command( 'pull', '--from', 'new-name' ), 'pull from name works');
    my $output
        = run_command( qw(search --type Pullall --regex .));
    my $expected = qr/new/;
    like( $output, $expected, 'Found our record' );

    $new_config_contents =~ s/url/pull-url/;
    Prophet::Util->write_file(
        file => $ENV{PROPHET_APP_CONFIG},
        content => $new_config_contents,
    );
    ok( run_command( 'pull', '--from', 'new-name' ),
        'pull from name works with pull-url var',
    );

    $new_config_contents .= "\turl = don't-use-this";
    Prophet::Util->write_file(
        file => $ENV{PROPHET_APP_CONFIG},
        content => $new_config_contents,
    );
    ok( run_command( 'pull', '--from', 'new-name' ),
        'pull-url is preferred over url',
    );
};


as_charlie {
    (undef, $ENV{PROPHET_APP_CONFIG}) = tempfile( CLEANUP => ! $ENV{PROPHET_DEBUG} );
    ok( run_command( 'clone', '--from', "file://$path" ),
        'clone as charlie',
    );
};

is(database_uuid_for('alice'), database_uuid_for('charlie'), "pull propagated the database uuid properly");
isnt(replica_uuid_for('alice'), replica_uuid_for('charlie'), "pull created a new replica uuid");

as_alice { check_replica('alice') };
as_bob { check_replica('bob') };
as_charlie { check_replica('charlie') };

sub check_replica {

    my $user = shift;

    my $cli = Prophet::CLI->new();
    my $replica = $cli->handle;
    my $changesets = $replica->fetch_changesets(after => 0);

    is(@$changesets, 2, "two changesets for $user");

    changeset_ok(
        changeset   => $changesets->[0],
        user        => $user,
        record_type => 'Bug',
        record_uuid => $bug_uuid,
        sequence_no => 1,
        merge       => $user ne 'alice',
        name        => "$user\'s first changeset",
    );
    changeset_ok(
        changeset   => $changesets->[1],
        user        => $user,
        record_type => 'Pullall',
        record_uuid => $pullall_uuid,
        sequence_no => 2,
        merge       => $user ne 'alice',
        name        => "$user\'s second changeset",
    );
}

sub changeset_ok {
    local $Test::Builder::Level = $Test::Builder::Level + 1;

    my %args = validate(@_, {
        changeset   => 1,
        user        => 1,
        sequence_no => 1,
        record_type => 1,
        record_uuid => 1,
        merge       => 1,
        name        => 0,
    });

    my $changeset = $args{changeset}->as_hash;

    my $changes = {
        $args{record_uuid} => {
            change_type  => 'add_file',
            record_type  => $args{record_type},
            prop_changes => {
                status => {
                    old_value => undef,
                    new_value => 'new',
                },
                from => {
                    old_value => undef,
                    new_value => 'alice',
                },
                creator => {
                    old_value => undef,
                    new_value => 'alice@example.com',
                },
                original_replica => {
                    old_value => undef,
                    new_value => replica_uuid_for('alice'),
                },
            },
        },
    };

    if ($args{merge}) {
        my $change_type = $args{sequence_no} > 1
                        ? 'update_file'
                        : 'add_file';

        my $prev_changeset_num = $args{sequence_no} > 1
                               ? $args{sequence_no} - 1
                               : undef;

    }

    is_deeply($changeset, {
        creator              => 'alice@example.com',
        created              => $changeset->{created},
        is_resolution        => undef,
        is_nullification     => undef,
        sequence_no          => $args{sequence_no},
        source_uuid          => replica_uuid_for($args{user}),
        original_sequence_no => $args{sequence_no},
        original_source_uuid => replica_uuid_for('alice'),
        changes              => $changes,
    }, $args{name});
}

