package Prophet::CLI::Command;
use Moose;

use Params::Validate qw(validate);

has cli => (
    is => 'rw',
    isa => 'Prophet::CLI',
    weak_ref => 1,
    handles => [
        qw/app_handle handle resdb_handle config/,
    ],
);

has context => (
    is => 'rw',
    isa => 'Prophet::CLIContext',
    handles => [ 
        qw/args  set_arg  arg  has_arg  delete_arg  arg_names/,
        qw/props set_prop prop has_prop delete_prop prop_names/,
        'add_to_prop_set', 'prop_set',
    ],

);


sub fatal_error {
    my $self   = shift;
    my $reason = shift;

    # always skip this fatal_error function when generating a stack trace
    local $Carp::CarpLevel = $Carp::CarpLevel + 1;

    die $reason . "\n";
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;

