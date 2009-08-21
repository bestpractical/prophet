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

    print "Records Database\n";
    print "----------------\n";

    print "Location:      ".$self->handle->url." (@{[ref($self->handle)]})\n";
    print "Database UUID: ".$self->handle->db_uuid."\n";
    print "Replica UUID:  ".$self->handle->uuid."\n";
    print "Changesets:    ".$self->handle->latest_sequence_no."\n";
    print "Known types:   ".join(',', @{$self->handle->list_types} )."\n\n";

    print "Resolutions Database\n";
    print "--------------------\n";

    print "Location:      "
        .$self->handle->resolution_db_handle->url." (@{[ref($self->handle)]})\n";
    print "Database UUID: "
        .$self->handle->resolution_db_handle->db_uuid."\n";
    print "Replica UUID:  "
        .$self->handle->resolution_db_handle->uuid."\n";
    print "Changesets:    "
        .$self->handle->resolution_db_handle->latest_sequence_no."\n";
    # known types get very unwieldy for resolutions
    # print "Known types:   "
    #     .join(',', @{$self->handle->resolution_db_handle->list_types} )."\n";
}

__PACKAGE__->meta->make_immutable;
no Any::Moose;

1;
