package Prophet::CLI::Command::Info;
use Any::Moose;
extends 'Prophet::CLI::Command';

sub ARG_TRANSLATIONS { shift->SUPER::ARG_TRANSLATIONS(),  l => 'local' };

sub run {
    my $self = shift;
    print "Working on prophet database: ".$self->handle->url.$/;

    print "Known types: ".join(',', @{$self->handle->list_types} ).$/;

}

__PACKAGE__->meta->make_immutable;
no Any::Moose;



1;

