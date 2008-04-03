use warnings;
use strict;

package Prophet::Sync::Source::SVN;
use base qw/Prophet::Sync::Source/;
use Params::Validate qw(:all);
use UNIVERSAL::require;

use SVN::Core;
use SVN::Ra;
use SVN::Delta;

use Prophet::Handle;
use Prophet::Sync::Source::SVN::ReplayEditor;
use Prophet::Sync::Source::SVN::Util;
use Prophet::ChangeSet;
use Prophet::Conflict;

__PACKAGE__->mk_accessors(qw/url ra prophet_handle ressource is_resdb pool/);

our $DEBUG = $Prophet::Handle::DEBUG;

=head2 setup

Open a connection to the SVN source identified by C<$self->url>.

XXX TODO, make the _prophet/ directory in the replica configurable

=cut

sub _get_ra {
    my $self = shift;
    my ( $baton, $ref ) = SVN::Core::auth_open_helper( Prophet::Sync::Source::SVN::Util->get_auth_providers );
    my $config = Prophet::Sync::Source::SVN::Util->svnconfig;
    return SVN::Ra->new( url => $self->url, config => $config, auth => $baton, pool => $self->pool ) ;
}

sub setup {
    my $self = shift;
    my $pool   = SVN::Pool->new;

    $self->pool($pool);

    $self->ra( $self->_get_ra );
    if ( $self->url =~ /^file:\/\/(.*)$/ ) {
        $self->prophet_handle( Prophet::Handle->new( { repository => $1 } ) );
    }
    if ( $self->url =~ m/_res$/ ) {

        # XXX: should probably just point to self
        return;
    }

    my $res_url = $self->url;
    $res_url =~ s/(\_res|)$/_res/;
    $self->ressource( __PACKAGE__->new( { url => $res_url, is_resdb => 1 } ) );
}

=head2 uuid

Return the replica SVN repository's UUID

=cut

sub uuid {
    my $self = shift;
    return $self->ra->get_uuid;
}

=head2 fetch_changesets { after => SEQUENCE_NO } 

Fetch all changesets from the source. 

Returns a reference to an array of L<Prophet::ChangeSet/> objects.


=cut

sub fetch_changesets {
    my $self = shift;
    my %args = validate( @_, { after => 1 } );
    my @results;

    my $first_rev = ( $args{'after'} + 1 ) || 1;

    # XXX TODO we should  be using a svn get_log call here rather than simple iteration
    # clkao explains that this won't deal cleanly with cases where there are revision "holes"
    for my $rev ( $first_rev .. $self->ra->get_latest_revnum ) {
        my $editor = Prophet::Sync::Source::SVN::ReplayEditor->new( _debug => 0 );
        $editor->ra( $self->_get_ra );
        my $pool = SVN::Pool->new_default;

        # This horrible hack is here because I have no idea how to pass custom variables into the editor
        $editor->{revision} = $rev;

        $self->ra->replay( $rev, 0, 1, $editor );
        push @results, $self->_recode_changeset( $editor->dump_deltas, $self->ra->rev_proplist($rev) );

    }

    return \@results;
}

sub _recode_changeset {
    my $self      = shift;
    my $entry     = shift;
    my $revprops  = shift;
    my $changeset = Prophet::ChangeSet->new(
        {   sequence_no          => $entry->{'revision'},
            source_uuid          => $self->uuid,
            original_source_uuid => $revprops->{'prophet:original-source'} || $self->uuid,
            original_sequence_no => $revprops->{'prophet:original-sequence-no'} || $entry->{'revision'},
            is_nullification     => ( ( $revprops->{'prophet:special-type'} || '' ) eq 'nullification' ) ? 1 : undef,
            is_resolution        => ( ( $revprops->{'prophet:special-type'} || '' ) eq 'resolution' ) ? 1 : undef,

        }
    );

    # add each node's changes to the changeset
    for my $path ( keys %{ $entry->{'paths'} } ) {
        if ( $path =~ qr|^(.+)/(.*?)/(.*?)$| ) {
            my ( $prefix, $type, $record ) = ( $1, $2, $3 );
            my $change = Prophet::Change->new(
                {   node_type   => $type,
                    node_uuid   => $record,
                    change_type => $entry->{'paths'}->{$path}->{fs_operation}
                }
            );
            for my $name ( keys %{ $entry->{'paths'}->{$path}->{prop_deltas} } ) {
                $change->add_prop_change(
                    name => $name,
                    old  => $entry->{paths}->{$path}->{prop_deltas}->{$name}->{'old'},
                    new  => $entry->{paths}->{$path}->{prop_deltas}->{$name}->{'new'},
                );
            }

            $changeset->add_change( change => $change );

        } else {
            warn "Discarding change to a non-record: $path" if $DEBUG;
        }

    }
    return $changeset;
}


=head2 last_changeset_from_source $SOURCE_UUID

Returns the last changeset id seen from the source identified by $SOURCE_UUID

=cut

sub last_changeset_from_source {
    my $self = shift;
    my ($source) = validate_pos( @_, { type => SCALAR } );
    my ( $stream, $pool );

    my $filename = join( "/", $self->prophet_handle->db_root, $Prophet::Handle::MERGETICKET_METATYPE, $source );
    my ( $rev_fetched, $props )
        = eval { $self->ra->get_file( $filename, $self->ra->get_latest_revnum, $stream, $pool ); };

    # XXX TODO this is hacky as hell and violates abstraction barriers in the name of doing things over the RA
    # because we want to be able to sync to a remote replica someday.

    

    return ( $props->{'last-changeset'} || 0 );

}

=head2 news_changesets_for

Returns the local changesets that are new to the replica $other.

=cut

sub new_changesets_for {
    my ($self, $other) = @_;

    my $since = $other->last_changeset_from_source( $self->uuid );
    warn $since;
    
}



1;
