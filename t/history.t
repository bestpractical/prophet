package App::Record;
use Any::Moose;
extends 'Prophet::Record';


package App::Record::Thingy;
use Any::Moose;
extends 'App::Record';

sub type {'foo'}

package main;
use warnings;
use strict;
use File::Temp qw/tempdir/;
$ENV{'PROPHET_REPO'} = tempdir( CLEANUP => ! $ENV{PROPHET_DEBUG}  ) . '/repo-' . $$;

use Prophet::Test tests => 8;
use Test::Exception;

    my $cli = Prophet::CLI->new();

$cli->handle->initialize;

    my $rec = App::Record::Thingy->new( handle => $cli->handle, type => 'foo' );

    ok( $rec->create( props => { foo => 'bar', point => '123' } ) );
is($rec->prop('foo'), 'bar');
is($rec->prop('point'), '123');
ok($rec->set_props(props => { foo => 'abc'}));
is($rec->prop('foo'), 'abc');
ok($rec->set_props(props => { foo => 'def'}));
is($rec->prop('foo'), 'def');
my @history = $rec->changesets();
is(scalar @history, 3);
