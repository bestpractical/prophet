use warnings;
use strict;

use Prophet::Test 'no_plan';
use Test::Exception;

use_ok('Prophet::Test::Arena');
use_ok('Prophet::Test::Participant');
my $arena = Prophet::Test::Arena->new();
$arena->setup( shift || 5 );
eval {
    for (1)
    {
        $arena->step('create_record');
    }

    for ( 1 .. 10 ) {
        $arena->step();
    }

    $arena->sync_all_pairs;
    $arena->sync_all_pairs;
    my $third = $arena->dump_state;
    diag(
        "now every txn has gotten to every peer. we could probably do more optimal routing, but that's not what we're testing"
    );

    # dump all chickens to a datastructure;
    $arena->sync_all_pairs;

    # dump all chickens to a datastructure and compare to the previous rev
    my $fourth = $arena->dump_state;
    is_deeply( $third, $fourth );
};
my $err = $@;
ok( !$err, "There was no error ($err)" );
my $Test = Test::Builder->new;
if ( grep { !$_ } $Test->summary ) {
    my $fname = join( '', sort map { substr( $_->name, 0, 1 ) } $arena->chickens ) . '.yml';
    diag "test failed... dumping recipe to $fname";
    YAML::Syck::DumpFile(
        $fname,
        {   chickens => [ map { $_->name } $arena->chickens ],
            recipe   => $arena->{history}
        }
    );
}

exit;
for ( $arena->chickens ) {
    warn $_->name;
    as_user(
        $_->name,
        sub {
            warn "==> hi";
            my $cli     = Prophet::CLI->new();
            my $handle  = $cli->handle;
            my $records = Prophet::Collection->new(
                handle => $handle,
                type   => 'Scratch'
            );
            $records->matching( sub {1} );
            use Data::Dumper;
            for ($records->items) {
                warn $_->uuid . ' : ' . Dumper( $_->get_props );
            }
        }
    );
}

exit;
