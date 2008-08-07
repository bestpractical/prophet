package Prophet::CLI::Command::Merge;
use Moose;
extends 'Prophet::CLI::Command';

sub run {
    my $self = shift;

    my (@alt_from, @alt_to);

    if ($self->has_arg('db_uuid')) {
        push @alt_from, join '/', $self->arg('from'), $self->arg('db_uuid');
        push @alt_to,   join '/', $self->arg('to'),   $self->arg('db_uuid');
    }

    my $source = Prophet::Replica->new(
        url       => $self->arg('from'),
        _alt_urls => \@alt_from,
    );

    my $target = Prophet::Replica->new(
        url       => $self->arg('to'),
        _alt_urls => \@alt_to,
    );

    $target->import_resolutions_from_remote_replica(
        from  => $source,
        force => $self->has_arg('force'),
    );

    $self->_do_merge( $source, $target );

    print "Merge complete.\n";
}

sub _do_merge {
    my ( $self, $source, $target ) = @_;

    if ( $target->uuid eq $source->uuid ) {
        $self->fatal_error(
                  "You appear to be trying to merge two identical replicas. "
                . "Either you're trying to merge a replica to itself or "
                . "someone did a bad job cloning your database." );
    }

    if ( !$target->can_write_changesets ) {
        $self->fatal_error( $target->url
                . " does not accept changesets. Perhaps it's unwritable."
        );
    }

    my $prefer = $self->arg('prefer') || 'none';

    my $resolver = $ENV{'PROPHET_RESOLVER'}
                   ? 'Prophet::Resolver::' . $ENV{'PROPHET_RESOLVER'}
                 : $prefer eq 'to'
                   ? 'Prophet::Resolver::AlwaysTarget'
                 : $prefer eq 'from'
                   ? 'Prophet::Resolver::AlwaysSource'
                   : ();

    my %import_args = (
        from  => $source,
        resdb => $self->app_handle->resdb_handle,
        force => $self->has_arg('force'),
    );

    $import_args{resolver_class} = $resolver
        if $resolver;

    if ($self->has_arg('verbose')) {
        $import_args{reporting_callback} = sub {
            my %args = @_;
            my $changeset = $args{changeset};
            print $changeset->as_string;
        };
    }

    $target->import_changesets(
        %import_args,
    );
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;

