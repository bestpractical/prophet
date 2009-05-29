package Prophet::CLI::Command::Merge;
use Any::Moose;
extends 'Prophet::CLI::Command';
with 'Prophet::CLI::ProgressBar';
with 'Prophet::CLI::MirrorCommand';

has source => ( isa => 'Prophet::Replica', is => 'rw');
has target => ( isa => 'Prophet::Replica', is => 'rw');

sub ARG_TRANSLATIONS { shift->SUPER::ARG_TRANSLATIONS(),  f => 'force' };

sub run {
    my $self = shift;

    Prophet::CLI->end_pager();
    $self->source( Prophet::Replica->get_handle(
        url       => $self->arg('from'),
        app_handle => $self->app_handle,
    ));

    $self->target( Prophet::Replica->get_handle(
        url       => $self->arg('to'),
        app_handle => $self->app_handle,
    ));

    
    return  unless $self->validate_merge_replicas($self->source => $self->target);
    if ( $self->source->can('read_changeset_index') && $self->target->url eq $self->app_handle->handle->url) {
        #   my $original_source = $self->source;
        #   $self->source($self->get_cache_for_source($original_source));
        #   $self->sync_cache_from_source( target=> $self->source, source => $original_source);
    }
    $self->target->import_resolutions_from_remote_replica(
        from  => $self->source,
        force => $self->has_arg('force'),
    ) if ($self->source->resolution_db_handle);
    
    my $changesets = $self->_do_merge();

    #Prophet::CLI->start_pager();
    $self->print_report($changesets) 
}

sub print_report {
    my $self       = shift;
    my $changesets = shift;
    if ( $self->has_arg('verbose') ) {
        if ( $changesets == 0 ) {
            print "No new changesets.\n";
        } elsif ( $changesets == 1 ) {
            print "Merged one changeset.\n";
        } else {
            print "Merged $changesets changesets.\n";
        }
    } else {
        print "Done.\n";
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

    my $source_latest = $self->source->latest_sequence_no() ||0;
    my $source_last_seen = $self->target->last_changeset_from_source($self->source->uuid);

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
        $import_args{reporting_callback} = $self->progress_bar( max => ($source_latest - $source_last_seen), format => "%30b %p %E\r" )
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
        : $prefer =~ /^(?:to|target)$/   ? 'Prophet::Resolver::AlwaysTarget'
        : $prefer =~ /^(?:from|source)$/ ? 'Prophet::Resolver::AlwaysSource'
        :                     ();
    return $resolver;
}


__PACKAGE__->meta->make_immutable;
no Any::Moose;

1;

