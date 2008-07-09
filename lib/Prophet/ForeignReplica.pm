package Prophet::ForeignReplica;
use Moose;
use Params::Validate qw(:all);
extends 'Prophet::Replica';

=head1 NAME

=head1 DESCRIPTION

This abstract baseclass implements the helpers you need to be able to easily sync a prophet replica with a "second class citizen" replica which can't exactly reconstruct changesets, doesn't use uuids to track records and so on.

=cut

sub BUILD {
    my $self = shift;
    my $cli  = Prophet::CLI->new();

    # XXX TODO this $cli object should be a Prophet::App object
    my $state_handle_url =      $cli->app_handle->default_replica_type . ":" . $cli->app_handle->handle->url;
    $self->log( "Connecting to state database ".$state_handle_url);
    $self->state_handle(
        Prophet::Replica->new(
            {   url => $state_handle_url,
                db_uuid => $self->state_db_uuid
            }
        )
    );
}

sub conflicts_from_changeset { return; }
sub can_write_changesets     {1}

sub record_resolutions { die "not for foreign replicas" }

sub import_resolutions_from_remote_source { warn 'no resdb'; return }

sub record_changes {
    my $self = shift;
    my ($changeset) = validate_pos( @_, { isa => 'Prophet::ChangeSet' } );
    $self->integrate_changes($changeset);
}

# XXX TODO = or do these ~always stay stubbed?
sub begin_edit  { }
sub commit_edit { }

use Data::UUID 'NameSpace_DNS';

# foreign replicas never have a db uuid
sub db_uuid { return undef }

sub uuid_for_url {
    my ( $self, $url ) = @_;
    return Data::UUID->new->create_from_name_str( NameSpace_DNS, $url );
}

sub prompt_for_login {
    my ( $self, $uri, $username ) = @_;

    my $password;

    # XXX belongs to some CLI callback
    use Term::ReadKey;
    local $| = 1;
    unless ($username) {
        print "Username for $uri: ";
        ReadMode 1;
        $username = ReadLine 0;
        chomp $username;
    }

    print "Password for $username @ $uri: ";
    ReadMode 2;
    $password = ReadLine 0;
    chomp $password;
    ReadMode 1;
    print "\n";
    return ( $username, $password );
}

our $REMOTE_ID_METATYPE = "_remote_id_map";

sub _remote_id_storage {
    my $self = shift;
    return $self->state_handle->metadata_storage( $REMOTE_ID_METATYPE,
        'prophet-uuid' )->(@_);
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;
