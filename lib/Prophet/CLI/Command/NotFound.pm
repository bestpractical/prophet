package Prophet::CLI::Command::NotFound;
use Moose;
extends 'Prophet::CLI::Command';

sub run {
    my $self = shift;
    $self->fatal_error( "The command you ran could not be found. Perhaps running '$0 help' would help?" );
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;

