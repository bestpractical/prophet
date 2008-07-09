package Prophet::CLI::Command::Merge;
use Moose;
extends 'Prophet::CLI::Command';

sub run {

    my $self = shift;

    my $source = Prophet::Replica->new( { url => $self->arg('from') } );
    my $target = Prophet::Replica->new( { url => $self->arg('to') } );

    $target->import_resolutions_from_remote_replica( from => $source );

    $self->_do_merge( $source, $target );

    print "Merge complete.\n";
}

sub _do_merge {
    my ( $self, $source, $target ) = @_;
    if ( $target->uuid eq $source->uuid ) {
        $self->fatal_error(
                  "You appear to be trying to merge two identical replicas. "
                . "Either you're trying to merge a replica to itself or "
                . "someone did a bad job cloning your database" );
    }

    my $prefer = $self->arg('prefer') || 'none';

    if ( !$target->can_write_changesets ) {
        $self->fatal_error( $target->url
                . " does not accept changesets. Perhaps it's unwritable or something"
        );
    }

    $target->import_changesets(
        from  => $source,
        resdb => $self->app_handle->resdb_handle,
        $ENV{'PROPHET_RESOLVER'}
        ? ( resolver_class => 'Prophet::Resolver::' . $ENV{'PROPHET_RESOLVER'} )
        : ( (   $prefer eq 'to'
                ? ( resolver_class => 'Prophet::Resolver::AlwaysTarget' )
                : ()
            ),
            (   $prefer eq 'from'
                ? ( resolver_class => 'Prophet::Resolver::AlwaysSource' )
                : ()
            )
        )
    );

}

__PACKAGE__->meta->make_immutable;
no Moose;

1;

