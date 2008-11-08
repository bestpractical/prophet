use warnings;
use strict;
use Prophet::Test tests => 2;

as_alice {
    run_output_matches('prophet', [qw(init)],
        [qr/Initialized your new Prophet database/]);
    run_output_matches('prophet', [qw(init)],
        [qr/Your Prophet database already exists/]);
};

1;

