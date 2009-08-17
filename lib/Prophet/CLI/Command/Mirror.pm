package Prophet::CLI::Command::Mirror;
use Any::Moose;
use Params::Validate qw/:all/;

extends 'Prophet::CLI::Command';
with 'Prophet::CLI::MirrorCommand';

has source => ( isa => 'Prophet::Replica', is => 'rw');
has target => ( isa => 'Prophet::Replica', is => 'rw');

sub ARG_TRANSLATIONS { shift->SUPER::ARG_TRANSLATIONS(),  f => 'force' };

sub usage_msg {
    my $self = shift;
    my $cmd = $self->cli->get_script_name;

    return <<"END_USAGE";
usage: ${cmd}mirror --from <url>
END_USAGE
}

sub run {
    my $self = shift;
    Prophet::CLI->end_pager();

    $self->print_usage if $self->has_arg('h');

    $self->validate_args();

    my $source = Prophet::Replica->get_handle( url        => $self->arg('from'), app_handle => $self->app_handle,);
    unless ( $source->replica_exists ) {
        print "The source replica '@{[$source->url]}' doesn't exist or is unreadable.";
        exit 1;
    }

    my $target = $self->get_cache_for_source($source);
    $self->sync_cache_from_source( target=> $target, source => $source);
    print "\nDone.\n";
}


sub validate_args {
    my $self = shift;
    unless ( $self->has_arg('from') ) {
        warn "No --from specified!\n";
        $self->print_usage;
    }
}

__PACKAGE__->meta->make_immutable;
no Any::Moose;

1;
