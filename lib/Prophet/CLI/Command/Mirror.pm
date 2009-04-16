package Prophet::CLI::Command::Mirror;
use Any::Moose;
use Params::Validate qw/:all/;

extends 'Prophet::CLI::Command';
with 'Prophet::CLI::MirrorCommand';

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

    my $target = $self->get_mirror_for_source($source);
    $self->sync_mirror_from_source( target=> $target, source => $source);
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
