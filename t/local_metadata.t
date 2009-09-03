use Prophet::Test tests => 6;

as_alice {
    my $cli = Prophet::CLI->new();
    $cli->handle->initialize;

	ok($cli->handle->store_local_metadata( foo => 'bar'));
	is($cli->handle->fetch_local_metadata( 'Foo' ), 'bar');
	ok($cli->handle->store_local_metadata( Foo => 'bartwo'));
	is($cli->handle->fetch_local_metadata( 'foo' ), 'bartwo');
	ok($cli->handle->store_local_metadata( foo => 'barTwo'));
	is($cli->handle->fetch_local_metadata( 'foo' ), 'barTwo');

};

