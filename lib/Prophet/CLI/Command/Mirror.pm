package Prophet::CLI::Command::Mirror;
use Any::Moose;
use Params::Validate qw/:all/;

extends 'Prophet::CLI::Command';
with 'Prophet::CLI::ProgressBar';

has source => ( isa => 'Prophet::Replica', is => 'rw');
has target => ( isa => 'Prophet::Replica', is => 'rw');

sub ARG_TRANSLATIONS { shift->SUPER::ARG_TRANSLATIONS(),  f => 'force' };

sub run {
    my $self = shift;
    Prophet::CLI->end_pager();

    $self->validate_args();


    my $source = Prophet::Replica->get_handle( url        => $self->arg('from'), app_handle => $self->app_handle,);
    unless ( $source->replica_exists ) {
        print "The source replica '@{[$source->url]}' doesn't exist or is unreadable.";
        exit 1;
    }

    my $target = Prophet::Replica->get_handle( url => 'prophet_cache:' . $source->uuid , app_handle => $self->app_handle );
    $target->uuid( $source->uuid );
    $target->resdb_replica_uuid( $source->resolution_db_handle->uuid );

    if ( !$target->replica_exists && !$target->can_initialize ) {
        die "The target replica path you specified can't be created.\n";
    }

    my %init_args = (
        db_uuid            => $source->db_uuid,
        replica_uuid       => $source->uuid,
        resdb_uuid         => $source->resolution_db_handle->db_uuid,
        resdb_replica_uuid => $source->resolution_db_handle->uuid,
    );
    $target->initialize(%init_args);    # XXX only do this when we need to
    print "Mirroring resolutions from " . $source->url . "\n";
    $target->resolution_db_handle->mirror_from(
        source => $source->resolution_db_handle,
        reporting_callback => $self->progress_bar( max => $source->resolution_db_handle->latest_sequence_no )
    );
    print "\nMirroring changesets from " . $source->url . "\n";
    $target->mirror_from(
        source             => $source,
        reporting_callback => $self->progress_bar( max => $source->latest_sequence_no )
    );
    print "\nDone.\n";
}
sub validate_args {
    my $self = shift;
    die "Please specify a --from.\n"
        unless $self->has_arg('from');
}

__PACKAGE__->meta->make_immutable;
no Any::Moose;

1;
