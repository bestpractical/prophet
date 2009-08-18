package Prophet::CLI::Command::Info;
use Any::Moose;
extends 'Prophet::CLI::Command';

sub ARG_TRANSLATIONS { shift->SUPER::ARG_TRANSLATIONS(),  l => 'local' };

sub usage_msg {
    my $self = shift;
    my $cmd = $self->cli->get_script_name;

    return <<"END_USAGE";
usage: ${cmd}info
END_USAGE
}

sub run {
    my $self = shift;

    $self->print_usage if $self->has_arg('h');

    print "Prophet database: ".$self->handle->url." (@{[ref($self->handle)]})".$/;
    print "Database UUID:    ".$self->handle->db_uuid.$/;
    print "Replica UUID:     ".$self->handle->uuid.$/;
    print "Changesets:       ".$self->handle->latest_sequence_no.$/;
    print "Known types:      ".join(',', @{$self->handle->list_types} ).$/;
}

__PACKAGE__->meta->make_immutable;
no Any::Moose;

1;
