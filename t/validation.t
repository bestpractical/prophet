package App::Record;
use Any::Moose;
extends 'Prophet::Record';

sub validate_prop_point {
    my ( $self, %args ) = @_;

    return 1 if $args{props}{point} =~ m/^\d+$/;
    $args{errors}{point} = 'must be numbers';
    return 0;

}

package main;
use warnings;
use strict;

use Prophet::Test tests => 2;
use Test::Exception;

as_alice {
    my $cli = Prophet::CLI->new();
    $cli->handle->initialize;
    my $rec = App::Record->new( handle => $cli->handle, type => 'foo' );

    ok( $rec->create( props => { foo => 'bar', point => '123' } ) );

    throws_ok {
        $rec->create( props => { foo => 'bar', point => 'orz' } );
    }
    qr/must be numbers/;
};

