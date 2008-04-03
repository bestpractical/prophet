use warnings;
use strict;

package Prophet::Sync::Source::RT;
use base qw/Prophet::Sync::Source/;
use Params::Validate qw(:all);
use UNIVERSAL::require;
use RT::Client::REST ();
use RT::Client::REST::User ();
use Memoize;
use Prophet::Handle;
use Prophet::ChangeSet;
use Prophet::Conflict;

__PACKAGE__->mk_accessors(qw/prophet_handle ressource is_resdb rt rt_url rt_query/);

our $DEBUG = $Prophet::Handle::DEBUG;

=head2 setup

Open a connection to the SVN source identified by C<$self->url>.

XXX TODO, make the _prophet/ directory in the replica configurable

=cut

use File::Temp 'tempdir';

sub setup {
    my $self = shift;
    my ($server, $type, $query) = $self->{url} =~ m/^rt:(.*?):(tickets):(.*)$/
        or die "Can't parse rt server spec";
    my $uri = URI->new($server);
    my ($username, $password);
    if (my $auth = $uri->userinfo) {
        ($username, $password) = split /:/, $auth, 2;
        $uri->userinfo(undef);
    }
    $self->rt_url( "$uri" );
    $self->rt_query( $query );
    $self->rt( RT::Client::REST->new(server => $server) );
    unless ($username) {
        # XXX belongs to some CLI callback
        use Term::ReadKey;
        local $| = 1;
        print "Username for $uri: ";
        ReadMode 1;
        $username = ReadLine 0;
        chomp $username;
        print "Password for $username @ $uri: ";
        ReadMode 2;
        $password = ReadLine 0;
        chomp $password;
        ReadMode 1;
        print "\n";
    }
    $self->rt->login(username => $username, password => $password);
    my $orz = tempdir();
    $self->{___Orz} = $orz;
    SVN::Repos::create($orz, undef, undef, undef, undef);
    $self->ressource( __PACKAGE__->new( { url => "file://$orz", is_resdb => 1 } ) );
}

sub fetch_resolutions { warn 'no resdb'}

=head2 uuid

Return the replica SVN repository's UUID

=cut

sub uuid {
    my $self = shift;
    return 1234;
    return Carp::cluck "need a uuid";
}

=head2 fetch_changesets { after => SEQUENCE_NO } 

Fetch all changesets from the source. 

Returns a reference to an array of L<Prophet::ChangeSet/> objects.


=cut

sub fetch_changesets {
    my $self = shift;
    my %args = validate( @_, { after => 1 } );

    my $first_rev = ( $args{'after'} + 1 ) || 1;

      my   @changesets;
    my %tix;
    for my $id ($self->_find_matching_tickets) {
        my @changesets = $self->_recode_transactions( ticket => $self->rt->show(type => 'ticket', id => $id), transactions => $self->_find_matching_transactions($id));  
    }

    my @results =  sort { $a->original_sequence_no <=> $b->original_sequence_no } @changesets;
    return \@results;
}

sub _recode_transactions {
    my $self = shift;
    my %args = validate( @_, { ticket => 1, transactions => 1 } );

    my $ticket = $args{'ticket'};

    $ticket->{'uuid'} = "NEED A UUID HERE";

    my $create_state = $ticket;
    my @changesets;
    for my $txn ( sort { $b->{'id'} <=> $a->{'id'} } @{ $args{'transactions'} } ) {
        warn "HANDLING " . $txn->{id} . " " . $txn->{Type};

        if ( $txn->{'Type'} eq 'Status' ) {
            $txn->{'Type'} = 'Set';
        }

        my $changeset = Prophet::ChangeSet->new(
            {   original_source_uuid => $self->uuid,
                original_sequence_no => $txn->{'id'},

            }
        );

        if ( $txn->{'Type'} eq 'Set' ) {
            my $change = Prophet::Change->new(
                {   node_type   => 'RT_Ticket',
                    node_uuid   => $self->rt_url . "/Ticket/" . $create_state->{'id'},
                    change_type => 'update_file'
                }
            );
            $changeset->add_change( { change => $change } );
            if ( $create_state->{ $txn->{Field} } eq $txn->{'NewValue'} ) {
                $create_state->{ $txn->{Field} } = $txn->{'OldValue'};
            } else {
                die $create_state->{ $txn->{Field} } . " != " . $txn->{'NewValue'};
            }
            $change->add_prop_change(
                name => $txn->{'Field'},
                old  => $txn->{'OldValue'},
                new  => $txn->{'NewValue'}

            );

        } elsif ( $txn->{'Type'} eq 'Create' ) {
            my $change = Prophet::Change->new(
                {   node_type   => 'RT_Ticket',
                    node_uuid   => $self->rt_url . "/Ticket/" . $create_state->{'id'},
                    change_type => 'create_file'
                }
            );
            $changeset->add_change( { change => $change } );
            for my $name ( keys %$create_state ) {

                $change->add_prop_change(
                    name => $name,
                    old  => undef,
                    new  => $create_state->{$name},
                );

            }

        } elsif ( $txn->{'Type'} eq 'AddLink' ) {
            my $change = Prophet::Change->new(
                {   node_type   => 'RT_Link',
                    node_uuid   => $self->rt_url . "/Link/" . $txn->{'id'},
                    change_type => 'create_file'
                }
            );
            $change->add_prop_change( name => 'url',    old => undef, new => $txn->{'NewValue'} );
            $change->add_prop_change( name => 'type',   old => undef, new => $txn->{'Field'} );
            $change->add_prop_change( name => 'ticket', old => undef, new => $ticket->{uuid} );
        } elsif ( $txn->{'Type'} eq 'Correspond' ) {
            my $change = Prophet::Change->new(
                {   node_type   => 'RT_Comment',
                    node_uuid   => $self->rt_url . "/Transaction/" . $txn->{'id'},
                    change_type => 'create_file'
                }
            );
            $change->add_prop_change(
                name => 'content',
                old  => undef,
                new  => $txn->{'Content'}
            );
            $change->add_prop_change(
                name => 'ticket',
                old  => undef,
                new  => $ticket->{uuid},
            );

        } elsif ( $txn->{'Type'} eq 'AddWatcher' || $txn->{'Type'} eq 'DelWatcher' ) {
            my $watcher_type = $txn->{'Field'};

            my $add = $self->resolve_user_id_to_email( $txn->{'NewValue'} );
            my $del = $self->resolve_user_id_to_email( $txn->{'OldValue'} );

            my @watchers = split( /\s*,\s*/, $create_state->{$watcher_type} );
            my @old_watchers = grep { $_ ne $add } @watchers, $del;
            $create_state->{$watcher_type} = join( ", ", @old_watchers );

            my $change = Prophet::Change->new(
                {   node_type   => 'RT_Ticket',
                    node_uuid   => $self->rt_url . "/Ticket/" . $create_state->{'id'},
                    change_type => 'update_file'
                }
            );
            $changeset->add_change( { change => $change } );
            $change->add_prop_change(
                name => $txn->{'Field'},
                old  => join( ', ', @old_watchers ),
                new  => join( ', ', @watchers )
            );

        } else {
            die "Don't know how to ahndle a " . YAML::Dump($txn);
        }

        unshift @changesets, $changeset;
    }

    return \@changesets;

}


sub resolve_user_id_to_email {
    my $self  = shift;
    my $id = shift;
    return undef unless ($id);
     
     my $user = RT::Client::REST::User->new(rt => $self->rt, id =>  $id)->retrieve;
     return $user->email_address;

}

memoize 'resolve_user_id_to_email';


sub _find_matching_tickets {
    my $self = shift;

    # Find all stalled tickets
    my @tix = $self->rt->search(
        type  => 'ticket',
        query => $self->rt_query,
    );
    return @tix;

}

sub _find_matching_transactions {
    my $self = shift;
    my $ticket = shift;
    my @txns;
    for my $txn ($self->rt->get_transaction_ids (parent_id => $ticket ) ) {
           push @txns, $self->rt->get_transaction (parent_id => $ticket, id => $txn, type => 'ticket');
    }
    return \@txns;
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
    my ( $rev_fetched, $props ) = eval { $self->ra->get_file( $filename, $self->ra->get_latest_revnum, $stream, $pool ); };
    return ( $props->{'last-changeset'} || 0 );

}


1;
