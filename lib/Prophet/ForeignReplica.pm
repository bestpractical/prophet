package Prophet::ForeignReplica;
use Any::Moose;
use Params::Validate qw(:all);
extends 'Prophet::Replica';

=head1 NAME

=head1 DESCRIPTION

This abstract baseclass implements the helpers you need to be able to easily sync a prophet replica with a "second class citizen" replica which can't exactly reconstruct changesets, doesn't use uuids to track records and so on.

=cut

sub fetch_local_metadata { my $self = shift;
    my $key = shift;
    $self->app_handle->handle->fetch_local_metadata( $self->uuid . "-".$key )
    
    }
sub store_local_metadata { my $self = shift;
    my $key = shift;
    my $value = shift;
   $self->app_handle->handle->store_local_metadata( $self->uuid."-".$key => $value);
    
    
    }




sub conflicts_from_changeset { return; }
sub can_write_changesets     {1}

sub record_resolutions { die "Resolution handling is not for foreign replicas" }

sub import_resolutions_from_remote_source {
    warn 'resdb not implemented yet';
    return
}

=head3 record_changes L<Prophet::ChangeSet>

Integrate all changes in this changeset.

=cut


sub record_changes {
    my $self = shift;
    my ($changeset) = validate_pos( @_, { isa => 'Prophet::ChangeSet' } );
    $self->integrate_changes($changeset);
}

# XXX TODO = or do these ~always stay stubbed?
sub begin_edit  { }
sub commit_edit { }


# foreign replicas never have a db uuid
sub db_uuid { return undef }

sub uuid_for_url {
    my ( $self, $url ) = @_;
    return $self->uuid_generator->create_string_from_url( $url );
}

sub prompt_for_login {
    my ( $self, $uri, $username ) = @_;

    my $password;

    my $was_in_pager = Prophet::CLI->in_pager();
    Prophet::CLI->end_pager();
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
    Prophet::CLI->start_pager() if ($was_in_pager);
    return ( $username, $password );
}

sub log {
    my $self = shift;
    my ($msg) = validate_pos(@_, 1);
    Carp::confess unless ($self->app_handle);
    $self->app_handle->log($self->url.": " .$msg);
}


no Any::Moose;
__PACKAGE__->meta->make_immutable;

1;
