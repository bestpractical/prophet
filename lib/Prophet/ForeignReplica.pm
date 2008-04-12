use warnings;
use strict;

package Prophet::ForeignReplica;
use base qw/Prophet::Replica/;
use Params::Validate qw(:all);

=head1 NAME

=head1 DESCRIPTION

This abstract baseclass implements the helpers you need to be able to easily sync a prophet replica with a "second class citizen" replica which can't exactly reconstruct changesets, doesn't use uuids to track records and so on.

=cut

sub setup {
    my $self = shift;
    my $cli = Prophet::CLI->new();

    $self->state_handle( Prophet::Replica->new({ url => "svn:".$cli->app_handle->handle->url, db_uuid => $self->state_db_uuid }) );
}

sub conflicts_from_changeset              { return; }
sub can_write_changesets                    {1}

sub record_resolutions { die "not for foreign replicas" }

sub import_resolutions_from_remote_source { warn 'no resdb'; return }

sub record_changeset {
    my $self = shift;
    my ($changeset) = validate_pos( @_, { isa => 'Prophet::ChangeSet' } );
    for my $change ( $changeset->changes ) {
        my $result = $self->_integrate_change( $change, $changeset );
    }
}

# XXX TODO = or do these ~always stay stubbed?
sub begin_edit {}
sub commit_edit{}



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
    if ($username) {
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
    return $self->state_handle->metadata_storage( $REMOTE_ID_METATYPE, 'prophet-uuid' )->(@_);
}

1;
