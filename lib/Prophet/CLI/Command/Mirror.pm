package Prophet::CLI::Command::Mirror;
use Any::Moose;
use Params::Validate qw/:all/;
use Time::Progress;

extends 'Prophet::CLI::Command';

has source => ( isa => 'Prophet::Replica', is => 'rw');
has target => ( isa => 'Prophet::Replica', is => 'rw');

sub ARG_TRANSLATIONS { shift->SUPER::ARG_TRANSLATIONS(),  f => 'force' };

sub run {
    my $self = shift;
    Prophet::CLI->end_pager();

    $self->validate_args();

    $self->set_arg( 'to' => 'prophet_cache:' . $self->app_handle->handle->url . '/remote-replica-cache/' );

    my $source = Prophet::Replica->get_handle(
        url        => $self->arg('from'),
        app_handle => $self->app_handle,
    );
    unless ( $source->replica_exists ) {
        print "The source replica '@{[$source->url]}' doesn't exist or is unreadable.";
        exit 1;
    }

    my $target = Prophet::Replica->get_handle(
        url        => $self->arg('to'),
        app_handle => $self->app_handle,
    );
    $target->uuid( $source->uuid );

    my $target_resdb = Prophet::Replica->get_handle(
        app_handle => $self->app_handle,
        url        => $self->arg('to')
    );
    $target_resdb->uuid($source->resolution_db_handle->uuid);


    if ( !$target->replica_exists && !$target->can_initialize ) {
        die "The target replica path you specified can't be created.\n";
    }

    my %init_args = (
        db_uuid            => $source->db_uuid,
        replica_uuid       => $source->uuid,
    );
    my %resdb_init_args = (
        db_uuid         => $source->resolution_db_handle->db_uuid,
        replica_uuid => $source->resolution_db_handle->uuid,
    );
    $target->initialize(%resdb_init_args);    # XXX only do this when we need to
    $target_resdb->initialize(%init_args);    # XXX only do this when we need to
    print "Mirroring resolutions from ".$source->url."\n";
    $target->mirror_from(source => $source->resolution_db_handle, 
            reporting_callback => $self->progress_bar( max => $source->resolution_db_handle->latest_sequence_no));
    print "\nMirroring changesets from ".$source->url."\n";
    $target->mirror_from(source => $source,
            reporting_callback => $self->progress_bar( max => $source->latest_sequence_no));
    print "\nDone.\n";
}
sub validate_args {
    my $self = shift;
    die "Please specify a --from.\n"
        unless $self->has_arg('from');
}

sub progress_bar { 
    my $self = shift;
    my %args = validate(@_, {max => 1});
    my $bar = Time::Progress->new();
    $bar->attr(max => $args{max});
    my $bar_count = 0;
    return sub {
       print $bar->report( "%30b %p %L (%E remaining)\r", ++$bar_count );
    }

}

__PACKAGE__->meta->make_immutable;
no Any::Moose;

1;
