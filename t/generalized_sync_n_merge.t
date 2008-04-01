use warnings;
use strict;

use Prophet::Test 'no_plan';
use Test::Exception;

use_ok('Prophet::Test::Arena');
use_ok('Prophet::Test::Participant');

my $arena = Prophet::Test::Arena->new();
$arena->setup(5);

for(1..3) {
    $arena->step('create_record');
}

for(1..5) {
    $arena->step();
}

$arena->sync_all_pairs;
exit;
for (@{$arena->chickens}) {
    warn $_->name;
    as_user( $_->name, sub {
                 warn "==> hi";
                 my $cli = Prophet::CLI->new();
                 my $handle = $cli->handle;
                 my $records = Prophet::Collection->new
                     (handle => $handle,
                      type => 'Scratch');
                 $records->matching(sub { 1 });
                 use Data::Dumper;
                 for (@{$records->as_array_ref}) {
                     warn $_->uuid.' : '.Dumper($_->get_props);
                 }
             });
}

exit;
;
