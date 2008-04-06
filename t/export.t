#!/usr/bin/perl

use warnings;
use strict;
use Test::Exception;

use Prophet::Test tests => 12;
use Test::Exception;

as_alice {
    run_ok( 'prophet-node-create', [qw(--type Bug --status new --from alice )], "Created a record as alice" );
    run_output_matches( 'prophet-node-search', [qw(--type Bug --regex .)], [qr/new/], " Found our record" );
};

diag('Bob syncs from alice');

my $record_id;

use File::Temp 'tempdir';

as_bob {

    run_ok( 'prophet-node-create', [qw(--type Dummy --ignore yes)], "Created a dummy record" );

    run_ok( 'prophet', ['merge', '--to', repo_uri_for('bob'), '--from', repo_uri_for('alice') ], "Sync ran ok!" );

    # check our local replicas
    my ( $ret, $out, $err ) = run_script( 'prophet-node-search', [qw(--type Bug --regex .)] );
    like( $out, qr/new/, "We have the one node from alice" );
    if ( $out =~ /^(.*?)\s./ ) {
        $record_id = $1;
    }
    diag($record_id);

    run_ok( 'prophet-node-update', [ '--type', 'Bug', '--uuid', $record_id, '--status' => 'stalled' ] );
    run_output_matches(
        'prophet-node-show',
        [ '--type',            'Bug',             '--uuid', $record_id ],
        [ 'id: ' . $record_id, 'status: stalled', 'from: alice' ],
        'content is correct'
    );

    my $path = Path::Class::dir->new( tempdir( CLEANUP => $ENV{TEST_VERBOSE} ) );

    run_ok( 'prophet', [ 'export', '--path', $path ] );
    my $cli = Prophet::CLI->new;
    $path = $path->subdir( $cli->handle->db_uuid );
    ok( -d $path,                       'found db-uuid root '.$path );
    ok( -e $path->file('replica-uuid'), 'found replica uuid file' );
    lives_and {
        is( $path->file('replica-uuid')->slurp, replica_uuid() );
    };

    ok( -e $path->file('changesets.idx'), 'found changesets index' );
    my $latest = $path->file('latest')->slurp;
    is($latest, 5);
    use_ok('Prophet::Replica::HTTP');
    my $changesets = Prophet::Replica->new({ url => 'prophet:file://'.$path} )->fetch_changesets( after => 0 );
    is( $#{ $changesets}, 4, "We found a total of 5 changesets");

};

