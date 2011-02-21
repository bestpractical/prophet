package Prophet::CLI::MirrorCommand;
use Any::Moose 'Role';
with 'Prophet::CLI::ProgressBar';
use Params::Validate ':all';



sub get_cache_for_source {
    my $self = shift;
    my ($source) = validate_pos(@_,{isa => 'Prophet::Replica'});
    my $target = Prophet::Replica->get_handle( url => 'prophet_cache:' . $source->uuid , app_handle => $self->app_handle );

    if ( !$target->replica_exists && !$target->can_initialize ) {
        die "The target replica path you specified can't be created.\n";
    }

    $target->initialize_from_source($source);
    return $target;
}

sub sync_cache_from_source {
    my $self = shift;
    my %args = validate(@_, { target => { isa => 'Prophet::Replica::prophet_cache'}, source => { isa => 'Prophet::Replica'}});

    if ($args{target}->latest_sequence_no == $args{source}->latest_sequence_no) {
        print "Mirror of ".$args{source}->url. " is already up to date\n";
        return 
    }

    print "Mirroring resolutions from " . $args{source}->url . "\n";
    $args{target}->resolution_db_handle->mirror_from(
        source => $args{source}->resolution_db_handle,
        reporting_callback => $self->progress_bar( max => ($args{source}->resolution_db_handle->latest_sequence_no ||0) )
    );
    print "\nMirroring changesets from " . $args{source}->url . "\n";
    $args{target}->mirror_from(
        source             => $args{source},
        reporting_callback => $self->progress_bar( max => ($args{source}->latest_sequence_no ||0) )
    );
}

no Any::Moose 'Role';

1;

