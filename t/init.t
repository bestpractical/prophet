use warnings;
use strict;
use Prophet::Test tests => 2;

as_alice {
    my $output = run_command( qw(init) );
    like( $output, qr/Initialized your new Prophet database/, 'init' );
    ( undef, my $error ) = run_command( qw(init) );
    like( $error, qr/Your Prophet database already exists/,
        'init existing replica');
};

