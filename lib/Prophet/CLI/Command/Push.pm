package Prophet::CLI::Command::Push;
use Any::Moose;
extends 'Prophet::CLI::Command::Merge';

sub run {
    my $self = shift;

    Prophet::CLI->end_pager();

    $self->validate_args;

    # sub out friendly names for replica URLs if possible
    my %previous_sources_by_name_push_url
        = $self->app_handle->config->sources( variable => 'push-url' );
    my %previous_sources_by_name_url = $self->app_handle->config->sources;

    my $original_to = $self->arg('to');
    $self->set_arg( 'to' => exists $previous_sources_by_name_push_url{$self->arg('to')}
        ? $previous_sources_by_name_push_url{$self->arg('to')}
        : exists $previous_sources_by_name_url{$self->arg('to')}
        ? $previous_sources_by_name_url{$self->arg('to')}
        : $self->arg('to')
    );

    $self->set_arg( from =>  $self->handle->url );
    $self->set_arg( db_uuid => $self->handle->db_uuid );

    $self->SUPER::run();

    # we want to record only the replica we're pushing TO, and only if we
    # weren't using a friendly name already
    $self->record_replica_in_config($self->arg('to'), $self->target->uuid)
        if $self->arg('to') eq $original_to;
}

sub validate_args {
    my $self = shift;

    die "Please specify a --to.\n" unless $self->context->has_arg('to');
}

__PACKAGE__->meta->make_immutable;
no Any::Moose;



1;

