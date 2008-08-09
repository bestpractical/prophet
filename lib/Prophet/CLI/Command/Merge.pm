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

    my $changesets = $self->_do_merge( $source, $target );

    if ($changesets == 0) {
        print "No new changesets.\n";
    }
    elsif ($changesets == 1) {
        print "Merged one changeset.\n";
    }
    else {
        print "Merged $changesets changesets.\n";
    }
}

=head2 _do_merge $source $target

Merges changesets from the source replica into the target replica.

Fails fatally if the source and target are the same, or the target is
not writable.

Conflicts are resolved by either the resolver specified in the
C<PROPHET_RESOLVER> environmental variable, the C<prefer> argument
(can be set to C<to> or C<from>, in which case Prophet will
always prefer changesets from one replica or the other), or by
using a default resolver.

Returns the number of changesets merged.

=cut

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
        resdb => $self->resdb_handle,
        force => $self->has_arg('force'),
    );

    $import_args{resolver_class} = $resolver
        if $resolver;

    my $changesets = 0;
    my $verbose = $self->has_arg('verbose');

    $import_args{reporting_callback} = sub {
        my %args = @_;
        my $changeset = $args{changeset};
        print $changeset->as_string if $verbose;
        $changesets++;
    };

    $target->import_changesets(
        %import_args,
    );

    return $changesets;
}

__PACKAGE__->meta->make_immutable;
no Moose;

1;

