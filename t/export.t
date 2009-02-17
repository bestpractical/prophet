#!/usr/bin/perl

use warnings;
use strict;

use Prophet::Test tests => 17;
use Test::Exception;
as_alice {
    run_ok('prophet', [qw(init)]);
    run_ok( 'prophet', [qw(create --type Bug -- --status new --from alice )], "Created a record as alice" );
    run_output_matches( 'prophet', [qw(search --type Bug --regex .)], [qr/new/], [], " Found our record" );
};

diag('Bob syncs from alice');

my $record_id;

use File::Temp 'tempdir';

as_bob {


    diag repo_uri_for('bob');
    diag repo_uri_for('alice');

    run_ok( 'prophet', [ 'clone', '--from', repo_uri_for('alice'), '--force' ], "Sync ran ok!" );
    run_ok( 'prophet', [qw(create --type Dummy -- --ignore yes)], "Created a dummy record" );

    # check our local replicas
    my ( $ret, $out, $err ) = run_script( 'prophet', [qw(search --type Bug --regex .)] );
    like( $out, qr/new/, "We have the one record from alice" );
    if ( $out =~ /'uuid': '(.*?)'\s./ ) {
        $record_id = $1;
    }
    diag($record_id);

    run_ok( 'prophet', [ 'update', '--type', 'Bug', '--uuid', $record_id, '--', '--status' => 'stalled' ] );
    run_output_matches(
        'prophet',
        ['show', '--type', 'Bug', '--uuid', $record_id, '--batch'],
        [
            qr/id: (\d+) \($record_id\)/,
              'creator: alice',
              'from: alice',
              'original_replica: ' . replica_uuid_for('alice'),
              'status: stalled',
        ], [],
        'content is correct'
    );

    my $path = tempdir( CLEANUP => ! $ENV{PROPHET_DEBUG} ) ;

    run_ok( 'prophet', [ 'export', '--path', $path ] );
    my $cli = Prophet::CLI->new;
    ok( -d $path,                       'found db-uuid root ' . $path );
    ok( -e File::Spec->catdir($path => 'replica-uuid'), 'found replica uuid file' );
    lives_and {
        is( Prophet::Util->slurp(File::Spec->catdir($path => 'replica-uuid')), replica_uuid() );
    };

    ok( -e File::Spec->catfile($path => 'changesets.idx'), 'found changesets index' );
    my $latest = Prophet::Util->slurp(File::Spec->catfile($path => 'latest-sequence-no'));
    is( $latest, $cli->handle->latest_sequence_no );
    use_ok('Prophet::Replica::prophet');
    diag("Checking changesets in $path");
    my $changesets =  Prophet::Replica->get_handle( { url => 'prophet:file://' . $path, app_handle => Prophet::CLI->new->app_handle } )->fetch_changesets( after => 0 );
    my @changesets = grep {$_->has_changes} @$changesets;
    is( $#changesets, 2, "We found a total of 3 changesets" );
    # XXX: compare the changeset structure
    is( lc( $changesets->[-1]->{source_uuid} ), lc( $changesets->[-1]->{original_source_uuid} ) );


};

