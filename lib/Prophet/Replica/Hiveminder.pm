use warnings;
use strict;

package Prophet::Replica::Hiveminder;
use base qw/Prophet::ForeignReplica/;
use Params::Validate qw(:all);
use UNIVERSAL::require;

use Net::Jifty;

use URI;
use Memoize;
use Prophet::Handle;
use Prophet::ChangeSet;
use Prophet::Replica::Hiveminder::PullEncoder;
use App::Cache;

__PACKAGE__->mk_accessors(qw/m hm_url/);

our $DEBUG = $Prophet::Handle::DEBUG;


=head2 setup

Open a connection to the SVN source identified by C<$self->url>.

XXX TODO, make the _prophet/ directory in the replica configurable

=cut

use File::Temp 'tempdir';

sub setup {
    my $self = shift;
    my ( $server, $type, $query ) = $self->{url} =~ m/^hiveminder:(.*?)\|(.*?)\|(.*)$/
        or die "Can't parse hiveminder server spec";
    my $uri = URI->new($server);
    my ( $username, $password );
    if ( my $auth = $uri->userinfo ) {
        ( $username, $password ) = split /:/, $auth, 2;
        $uri->userinfo(undef);
    }
    $self->hm_url("$uri");

    $self->hm( Jifyt RT::Client::REST->new( server => $server ) );
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


    $self->hm( Net::Jifty->new(site => $self->hm_url,
                        cookie_name => 'JIFTY_SID_HIVEMINDER',
    
                        email => $username,
                        password => $password
                        ));
    

    my $cli = Prophet::CLI->new();
    $self->state_handle( $cli->get_handle_for_replica( $self, 'state' ) );
}





=head2 uuid

Return the replica SVN repository's UUID

=cut

sub uuid {
    my $self = shift;
    return $self->uuid_for_url( join( '/', $self->hm_url, $self->hm->username ) );
}



=head2 fetch_changesets { after => SEQUENCE_NO } 

Fetch all changesets from the source. 

Returns a reference to an array of L<Prophet::ChangeSet/> objects.


=cut

sub fetch_changesets {
    my $self = shift;
    my %args = validate( @_, { after => 1 } );

    my $first_rev = ( $args{'after'} + 1 ) || 1;

    my @changesets;
    my %tix;
    my $recoder = Prophet::Replica::Hiveminder::PullEncoder->new( { sync_source => $self } );
    for my $task ( $self->find_matching_tasks ) {
        push @changesets, @{ $recoder->run(
                task => $task,
                transactions => $self->find_matching_transactions( task => $task->{id}, starting_transaction => $first_rev )) };
    }

    return [ sort { $a->original_sequence_no <=> $b->original_sequence_no } @changesets ];
}

sub find_matching_tasks {
    my $self  = shift;
    my $tasks = $self->hm->act(
        'TaskSearch',
        owner        => 'me',
        group        => 0,
        requestor    => 'me',
        not_complete => 1,

    )->{content}->{tasks};
    return $tasks;
}

sub prophet_has_seen_transaction { warn "not yet"; return undef }


# hiveminder transaction ~= prophet changeset
# hiveminder taskhistory ~= prophet change
# hiveminder taskemail ~= prophet change
sub find_matching_transactions {
    my $self = shift;
    my %args = validate( @_, { task => 1, starting_transaction => 1 } );

    my ($task) = validate_pos( @_, 1 );
    my $txns = $self->hm->search( 'TaskTransaction', task_id => $args{task} );
    foreach my $txn ( @{ $txns || [] } ) {
        next if $txn < $args{'starting_transaction'};        # Skip things we've pushed

        next if $self->prophet_has_seen_transaction($txn);
        $txn->{history_entries} = $self->hm->search( 'TaskHistory', transaction_id => $txn->{'id'} );
        $txn->{email_entries} = $self->hm->search( 'TaskEmail', transaction_id => $txn->{'id'} );
    }
    return $txns;

}

1;
