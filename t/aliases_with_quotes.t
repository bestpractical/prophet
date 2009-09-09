#!/usr/bin/perl -w
#
use warnings;
use strict;
use Prophet::Test tests => 15;

as_alice {
    run_command('init');
    my ( $output, $error ) =
      run_command( qw/create --type Bug --/, 'summary=foo bar' );
    our $bug_id;
    like(
        $output,
        qr/Created Bug \d+ \((\S+)\)(?{ $bug_id = $1 })/,
        "created bug"
    );
    use_ok('Prophet::CLI');
    my $a = Prophet::CLI->new();
    can_ok( $a,             'app_handle' );
    can_ok( $a->app_handle, 'config' );
    my $config = $a->config;
    $config->load;

    is_deeply( scalar $config->aliases, {}, 'initial alias is empty' );

    # no news is good news
    my @cmds = (
        {
            cmd     => ['show'],
            output  => qr/No aliases for the current repository/,
            comment => 'show empty aliases',
        },
        {

            # this alias is bad, please don't use it in real life
            cmd => [ 'add', 'balanced_1=search --type Bug -- summary="foo bar"' ],
            comment => 'add a new alias',
        },
        {

            # this alias is bad, please don't use it in real life
            cmd => [ 'add', 'balanced_2=search --type Bug -- summary "foo bar"' ],
            comment => 'add a new alias',
        },
    );

    for my $item (@cmds) {
        my $exp_output = defined $item->{output} ? $item->{output} : qr/^$/;
        my $exp_error  = defined $item->{error}  ? $item->{error}  : qr/^$/;

        my ( $got_output, $got_error ) =
          run_command( 'aliases', @{ $item->{cmd} } );

        like( $got_output, $exp_output, $item->{comment} . ' (STDOUT)' );
        like( $got_error,  $exp_error,  $item->{comment} . ' (STDERR)' );
    }

    ($output, $error) = run_command(qw/search --type Bug -- summary/, 'foo bar' );
    ($output) = run_command('balanced_1');
    like( $output, qr/$bug_id/, 'quote in aliase like --summary="foo bar"' );
    ($output) = run_command('balanced_2');
    like( $output, qr/$bug_id/, 'quote in aliase like --summary "foo bar"' );
};
