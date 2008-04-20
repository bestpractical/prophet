#!/usr/bin/perl

use warnings;
use strict;
use Test::Exception;

use Prophet::Test tests => 16;
use Test::Exception;

as_alice {
    run_ok( 'prophet', [qw(create --type Bug --status new --from alice )], "Created a record as alice" );
    run_output_matches( 'prophet', [qw(search --type Bug --regex .)], [qr/new/], " Found our record" );
};

diag('Bob syncs from alice');

my $record_id;

use File::Temp 'tempdir';

as_bob {

    run_ok( 'prophet', [qw(create --type Dummy --ignore yes)], "Created a dummy record" );

    diag repo_uri_for('bob');
    diag repo_uri_for('alice');

    run_ok( 'prophet', [ 'merge', '--to', repo_uri_for('bob'), '--from', repo_uri_for('alice') ], "Sync ran ok!" );
    # check our local replicas
    my ( $ret, $out, $err ) = run_script( 'prophet', [qw(search --type Bug --regex .)] );
    like( $out, qr/new/, "We have the one record from alice" );
    if ( $out =~ /^(.*?)\s./ ) {
        $record_id = $1;
    }
    diag($record_id);

    run_ok( 'prophet', [ 'update', '--type', 'Bug', '--uuid', $record_id, '--status' => 'stalled' ] );
    run_output_matches(
        'prophet',
        ['show', '--type',            'Bug',             '--uuid', $record_id ],
        [ 'id: ' . $record_id, 'status: stalled', 'from: alice' ],
        'content is correct'
    );

    my $path = Path::Class::dir->new( tempdir( CLEANUP => ! $ENV{TEST_VERBOSE} ) );

    run_ok( 'prophet', [ 'export', '--path', $path ] );
    my $cli = Prophet::CLI->new;
    $path = $path->subdir( $cli->app_handle->handle->db_uuid );
    ok( -d $path,                       'found db-uuid root ' . $path );
    ok( -e $path->file('replica-uuid'), 'found replica uuid file' );
    lives_and {
        is( $path->file('replica-uuid')->slurp, replica_uuid() );
    };

    ok( -e $path->file('changesets.idx'), 'found changesets index' );
    my $latest = $path->file('latest-sequence-no')->slurp;
    is( $latest, 5 );
    use_ok('Prophet::Replica::Native');
    diag("Checking changesets in $path");
    my $changesets = Prophet::Replica->new( { url => 'prophet:file://' . $path } )->fetch_changesets( after => 0 );
    is( $#{$changesets}, 4, "We found a total of 5 changesets" );

    # XXX: compare the changeset structure
    is( lc( $changesets->[-1]->{source_uuid} ), lc( $changesets->[-1]->{original_source_uuid} ) );


};

