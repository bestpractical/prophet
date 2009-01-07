package Prophet::CLI::Command::Merge;
use Moose;
extends 'Prophet::CLI::Command';

has source => ( isa => 'Prophet::Replica', is => 'rw');
has target => ( isa => 'Prophet::Replica', is => 'rw');


sub run {
    my $self = shift;

    $self->source( Prophet::Replica->get_handle(
        url       => $self->arg('from'),
        app_handle => $self->app_handle,
    ));

    $self->target( Prophet::Replica->get_handle(
        url       => $self->arg('to'),
        app_handle => $self->app_handle,
    ));


    
    return  unless $self->validate_merge_replicas($self->source => $self->target);

    $self->target->import_resolutions_from_remote_replica(
        from  => $self->source,
        force => $self->has_arg('force'),
    );

    my $changesets = $self->_do_merge();

    $self->print_report($changesets);
}

sub print_report {
    my $self = shift;
    my $changesets = shift;
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

=head2 _do_merge

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
    my ( $self) = @_;

    my %import_args = (
        from  => $self->source,
        resdb => $self->resdb_handle,
        force => $self->has_arg('force'),
    );

    local $| = 1;


    $import_args{resolver_class} = $self->merge_resolver();

    my $changesets = 0;

    my $source_latest = $self->source->latest_sequence_no() || 0;
    my $source_last_seen = $self->target->last_changeset_from_source($self->source->uuid) || 0;

    if( $self->has_arg('verbose') ) {
        print "Integrating changes from ".$source_last_seen . " to ". $source_latest."\n";
    }


    if( $self->has_arg('verbose') ) {
        $import_args{reporting_callback} = sub {
            my %args = @_;
            print $args{changeset}->as_string;
            $changesets++;
        };
    } else {
        require Time::Progress;
        my $progress = Time::Progress->new();
        $progress->attr( max => ($source_latest - $source_last_seen));

        $import_args{reporting_callback} = sub {
            my %args = @_;
            $changesets++;
            print $progress->report( "%30b %p %E // ". ($args{changeset}->created || 'Undated'). " " .(sprintf("%-12s",$args{changeset}->creator||'')) ."\r" , $changesets);

        };

    }

    $self->target->import_changesets( %import_args);
    return $changesets;
}

sub validate_merge_replicas {
    my $self = shift;
    my $source = shift;
    my $target = shift;

    if ( ! $target->replica_exists ) {
       $self->handle->log("The target (".$self->arg('to').") replica doesn't exist"); 
        return 0;
    }

    if ( ! $source->replica_exists ) {
       $self->handle->log("The source (".$self->arg('from').") replica doesn't exist"); 
        return 0;
    }


    if ( $target->uuid eq $source->uuid ) {
        $self->handle->log( "You appear to be trying to merge two identical replicas. Skipping.");
        return 0;
    }

    if ( !$target->can_write_changesets ) {
        $self->handle->log( $target->url . " does not accept changesets. Perhaps it's unwritable.");
        return 0;
    }
    return 1;
}

sub merge_resolver {
    my $self = shift;

    my $prefer = $self->arg('prefer') || 'none';

    my $resolver = $ENV{'PROPHET_RESOLVER'} ? 'Prophet::Resolver::' . $ENV{'PROPHET_RESOLVER'}
        : $prefer eq 'to'   ? 'Prophet::Resolver::AlwaysTarget'
        : $prefer eq 'from' ? 'Prophet::Resolver::AlwaysSource'
        :                     ();
    return $resolver;
}


__PACKAGE__->meta->make_immutable;
no Moose;

1;

