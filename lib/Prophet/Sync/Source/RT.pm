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
    return $self->uuid_for_url( join('/', $self->rt_url, $self->rt_query ) );

}

use Data::UUID 'NameSpace_DNS';

sub uuid_for_url {
    my ($self, $url) = @_;
    return Data::UUID->new->create_from_name_str( NameSpace_DNS, $url);
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
        push @changesets, @{ $self->_recode_transactions( ticket => $self->rt->show(type => 'ticket', id => $id), transactions => $self->_find_matching_transactions($id)) };
    }
    warn Dumper(\@changesets); use Data::Dumper;
    die 'not yet';
    my @results =  sort { $a->original_sequence_no <=> $b->original_sequence_no } @changesets;
    return \@results;
}

sub _recode_transactions {
    my $self = shift;
    my %args = validate( @_, { ticket => 1, transactions => 1 } );

    my $ticket = $args{'ticket'};

    $ticket->{'uuid'} = "NEED A UUID HERE";

    my $create_state = $ticket;
    map { $create_state->{$_} =~ s/ minutes$// }  qw(TimeWorked TimeLeft TimeEstimated);
    my @changesets;
    for my $txn ( sort { $b->{'id'} <=> $a->{'id'} } @{ $args{'transactions'} } ) {
        if ( my $sub = $self->can( '_recode_txn_' . $txn->{'Type'} ) ) {
            my $changeset = Prophet::ChangeSet->new(
                {
                    original_source_uuid => $self->uuid,
                    original_sequence_no => $txn->{'id'},
                }
            );
            $sub->( $self,
                ticket       => $ticket,
                create_state => $create_state,
                txn          => $txn,
                changeset    => $changeset );
            unshift @changesets, $changeset unless $changeset->is_empty;
        }
        else {
            warn "not handling txn type $txn->{Type} for $txn->{id} (Ticket $args{ticket}{id}) yet";
        }

    }

    return \@changesets;

}



sub _recode_txn_EmailRecord {
    return;
}

sub _recode_txn_Status {
    my $self = shift;
    my %args = validate( @_, { ticket => 1, txn => 1, create_state => 1, changeset => 1});

            $args{txn}->{'Type'} = 'Set';

        return $self->_recode_txn_Set(%args);
    }





sub _recode_txn_Set {
    my $self = shift;
    my %args = validate( @_, { ticket => 1, txn => 1, create_state => 1, changeset=>1});

            my $change = Prophet::Change->new(
                {   node_type   => 'RT_Ticket',
                    node_uuid   => $self->rt_url . "/Ticket/" . $args{'create_state'}->{'id'},
                    change_type => 'update_file'
                }
            );
            $args{'changeset'}->add_change( { change => $change } );
            if ( $args{'create_state'}->{ $args{txn}->{Field} } eq $args{txn}->{'NewValue'} ) {
                $args{'create_state'}->{ $args{txn}->{Field} } = $args{txn}->{'OldValue'};
            } else {
                die $args{'create_state'}->{ $args{txn}->{Field} } . " != " . $args{txn}->{'NewValue'};
            }
            $change->add_prop_change(
                name => $args{txn}->{'Field'},
                old  => $args{txn}->{'OldValue'},
                new  => $args{txn}->{'NewValue'}

            );

        }
        
sub _recode_txn_Create {
    my $self = shift;
    my %args = validate( @_, { ticket => 1, txn => 1, create_state => 1, changeset=>1});
        
            my $change = Prophet::Change->new(
                {   node_type   => 'RT_Ticket',
                    node_uuid   => $self->rt_url . "/Ticket/" . $args{'create_state'}->{'id'},
                    change_type => 'add_file'
                }
            );
            $args{'changeset'}->add_change( { change => $change } );
            for my $name ( keys %{$args{'create_state'}} ) {

                $change->add_prop_change(
                    name => $name,
                    old  => undef,
                    new  => $args{'create_state'}->{$name},
                );

            }
        }

sub _recode_txn_AddLink {
    my $self = shift;
    my %args = validate( @_, { ticket => 1, txn => 1, create_state => 1, changeset=>1});
            my $change = Prophet::Change->new(
                {   node_type   => 'RT_Link',
                    node_uuid   => $self->rt_url . "/Link/" . $args{'txn'}->{'id'},
                    change_type => 'add_file'
                }
            );
            $change->add_prop_change( name => 'url',    old => undef, new => $args{'txn'}->{'NewValue'} );
            $change->add_prop_change( name => 'type',   old => undef, new => $args{'txn'}->{'Field'} );
            $change->add_prop_change( name => 'ticket', old => undef, new => $args{ticket}->{uuid} );
        }
sub _recode_txn_Correspond {
    my $self = shift;
    my %args = validate( @_, { ticket => 1, txn => 1, create_state => 1, changeset=>1});
            my $change = Prophet::Change->new(
                {   node_type   => 'RT_Comment',
                    node_uuid   => $self->rt_url . "/Transaction/" . $args{'txn'}->{'id'},
                    change_type => 'add_file'
                }
            );
            $change->add_prop_change(
                name => 'content',
                old  => undef,
                new  => $args{'txn'}->{'Content'}
            );
            $change->add_prop_change(
                name => 'ticket',
                old  => undef,
                new  => $args{ticket}->{uuid},
            );
        }

sub _recode_txn_AddWatcher {
    my $self = shift;
    my %args = validate( @_, { ticket => 1, txn => 1, create_state => 1, changeset=>1});
        

            my $new_state = $args{'create_state'}->{ $args{'txn'}->{'Field'} };

            $args{'create_state'}->{ $args{'txn'}->{'Field'} } = $self->warp_list_to_old_value(
                $args{'create_state'}->{ $args{'txn'}->{'Field'} },

                $self->resolve_user_id_to_email( $args{'txn'}->{'NewValue'} ),
                $self->resolve_user_id_to_email( $args{'txn'}->{'OldValue'} )

            );

            my $change = Prophet::Change->new(
                {   node_type   => 'RT_Ticket',
                    node_uuid   => $self->rt_url . "/Ticket/" . $args{'create_state'}->{'id'},
                    change_type => 'update_file'
                }
            );
            $args{'changeset'}->add_change( { change => $change } );
            $change->add_prop_change(
                name => $args{'txn'}->{'Field'},
                old  => $args{'create_state'}->{ $args{'txn'}->{'Field'} },
                new  => $new_state
            );

        }
        
*_recode_txn_DelWatcher  = \&_recode_txn_AddWatcher;
sub _recode_txn_CustomField {
    my $self = shift;
    my %args = validate( @_, { ticket => 1, txn => 1, create_state => 1, changeset=>1});
        
            my $new = $args{'txn'}->{'NewValue'};
            my $old = $args{'txn'}->{'OldValue'};
            my $name;
            if ( $args{'txn'}->{'Description'} =~ /^(.*) $new added by/ ) {
                $name = $1;

            } elsif ( $args{'txn'}->{'Description'} =~ /^(.*) $old delete by/ ) {
                $name = $1;
            } else {
                die "Uh. what to do with txn descriotion " . $args{'txn'}->{'Description'};
            }

            $args{'txn'}->{'Field'} = "CF-" . $name;

            my $new_state = $args{'create_state'}->{ $args{'txn'}->{'Field'} };
            $args{'create_state'}->{ $args{'txn'}->{'Field'} } = $self->warp_list_to_old_value( $args{'create_state'}->{ $args{'txn'}->{'Field'} },
                $args{'txn'}->{'NewValue'}, $args{'txn'}->{'OldValue'} );

            my $change = Prophet::Change->new(
                {   node_type   => 'RT_Ticket',
                    node_uuid   => $self->url . "/Ticket/" . $args{'create_state'}->{'id'},
                    change_type => 'update_file'
                }
            );

            $args{'changeset'}->add_change( { change => $change } );
            $change->add_prop_change(
                name => $args{'txn'}->{'Field'},
                old  => $args{'create_state'}->{ $args{'txn'}->{'Field'} },
                new  => $new_state
            );
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

sub warp_list_to_old_value {
    my $self = shift;
    my $ticket_value = shift;
    my $add = shift;
    my $del = shift;

            my @new = split( /\s*,\s*/, $ticket_value );
            my @old = grep { $_ ne $add } @new, $del;
            return join( ", ", @old );
}

1;
