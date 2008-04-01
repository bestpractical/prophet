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

for(1..10) {
    $arena->step();
}

$arena;

exit;
;