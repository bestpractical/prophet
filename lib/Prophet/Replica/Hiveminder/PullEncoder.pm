use warnings;
use strict;

package Prophet::Replica::Hiveminder::PullEncoder;
use base qw/Class::Accessor/;
use Params::Validate qw(:all);
use UNIVERSAL::require;

use Memoize;

__PACKAGE__->mk_accessors(qw/sync_source/);

our $DEBUG = $Prophet::Handle::DEBUG;

sub run {
    my $self = shift;
    my %args = validate( @_, { task => 1, transactions => 1 } );

    warn YAML::Dump(\%args);
    warn "Working on " . $args{'task'}->{id};
    my @changesets;

    my $previous_state = $args{'task'};
    for my $txn ( sort { $b->{'id'} <=> $a->{'id'} } @{ $args{'transactions'} } ) {

        my $changeset = Prophet::ChangeSet->new(
            {   original_source_uuid => $self->sync_source->uuid,
                original_sequence_no => $txn->{'id'},
            }
        );
        # In Hiveminder, a changeset has only one change 
        my $change = Prophet::Change->new( {   node_type   => 'ticket',
            node_uuid   => $self->sync_source->uuid_for_remote_id( $args{'previous_state'}->{'id'} ),
            change_type => ($txn->{type} eq 'create' ? 'add_file' :'update_file' )

        }
        );
        warn "We're not yet detecting create vs update vs delete";
        $changeset->add_change({ change => $change});
        foreach my $entry ( @{ $txn->{'history_entries'} } ) {
            # Each of these entries is essentially a propchange
            $self->add_prop_change( change => $change, history_entry =>  $entry,
                    previous_state => $previous_state,
            );

        }

        foreach my $email (@{$txn->{email_entries}}) {
            if(my $sub = $self->can('_recode_email_'.'blah')) {
                $sub->( $self     => 
                    previous_state => $previous_state,
                    email       => $email,
                    txn       => $txn,
                    changeset => $changeset
                );
                }
        }


        $self->translate_prop_names($changeset);
        unshift @changesets, $changeset unless $changeset->is_empty;
    }
        return \@changesets;
}



sub add_prop_change {
    my $self = shift;
    my %args = validate( @_, {  history_entry => 1, previous_state => 1, change => 1 } );

    if ( $args{'previous_state'}->{ $args{history_entry}->{field} } eq $args{history_entry}->{'new_value'} ) {
        $args{'previous_state'}->{ $args{history_entry}->{field} } = $args{history_entry}->{'old_value'};
    } else {
        $args{'previous_state'}->{ $args{history_entry}->{field} } = $args{history_entry}->{'old_value'};
        warn $args{'previous_state'}->{ $args{history_entry}->{field} } . " != "
            . $args{history_entry}->{'new_value'} . "\n\n"
            . YAML::Dump( \%args );
    }
    $args{change}->add_prop_change(
        name => $args{history_entry}->{'field'},
        old  => $args{history_entry}->{'old_value'},
        new  => $args{history_entry}->{'new_value'}

    );

}

sub _recode_entry_create {
    my $self = shift;
    my %args = validate( @_, {  txn => 1, previous_state => 1, changeset => 1 } );

    my $change = Prophet::Change->new(
        {   node_type   => 'ticket',
            node_uuid   => $self->sync_source->uuid_for_remote_id( $args{'previous_state'}->{'id'} ),
            change_type => 'add_file'
        }
    );

    $args{'previous_state'}->{ $self->sync_source->uuid . '-id' } = delete $args{'previous_state'}->{'id'};

    $args{'changeset'}->add_change( { change => $change } );
    for my $name ( keys %{ $args{'previous_state'} } ) {

        $change->add_prop_change(
            name => $name,
            old  => undef,
            new  => $args{'previous_state'}->{$name},
        );

    }

    $self->_recode_content_update(%args);    # add the create content txn as a seperate change in this changeset

}

sub _recode_content_update {
    my $self   = shift;
    my %args   = validate( @_, {  txn => 1, previous_state => 1, changeset => 1 } );
    my $change = Prophet::Change->new(
        {   node_type => 'comment',
            node_uuid =>
                $self->sync_source->uuid_for_url( $self->sync_source->rt_url . "/transaction/" . $args{'txn'}->{'id'} ),
            change_type => 'add_file'
        }
    );
    $change->add_prop_change(
        name => 'type',
        old  => undef,
        new  => $args{'txn'}->{'Type'}
    );

    $change->add_prop_change(
        name => 'creator',
        old  => undef,
        new  => $args{'txn'}->{'Creator'}
    );
    $change->add_prop_change(
        name => 'content',
        old  => undef,
        new  => $args{'txn'}->{'Content'}
    );
    $change->add_prop_change(
        name => 'task',
        old  => undef,
        new  => $args{task}->{uuid},
    );
    $args{'changeset'}->add_change( { change => $change } );
}

*_recode_entry_Comment    = \&_recode_content_update;
*_recode_entry_Correspond = \&_recode_content_update;

sub _recode_entry_AddWatcher {
    my $self = shift;
    my %args = validate( @_, { txn => 1, previous_state => 1, changeset => 1 } );

    my $new_state = $args{'previous_state'}->{ $args{'txn'}->{'field'} };

    $args{'previous_state'}->{ $args{'txn'}->{'field'} } = $self->warp_list_to_old_value(
        $args{'previous_state'}->{ $args{'txn'}->{'field'} },

        $self->resolve_user_id_to( email => $args{'txn'}->{'new_value'} ),
        $self->resolve_user_id_to( email => $args{'txn'}->{'old_value'} )

    );

    my $change = Prophet::Change->new(
        {   node_type   => 'ticket',
            node_uuid   => $self->sync_source->uuid_for_remote_id( $args{'previous_state'}->{'id'} ),
            change_type => 'update_file'
        }
    );
    $args{'changeset'}->add_change( { change => $change } );
    $change->add_prop_change(
        name => $args{'txn'}->{'field'},
        old  => $args{'previous_state'}->{ $args{'txn'}->{'field'} },
        new  => $new_state
    );

}

*_recode_entry_DelWatcher = \&_recode_entry_AddWatcher;

sub resolve_user_id_to {
    my $self = shift;
    my $attr = shift;
    my $id   = shift;
    return undef unless ($id);

    my $user = Hiveminder::Client::REST::User->new( rt => $self->sync_source->rt, id => $id )->retrieve;
    return $attr eq 'name' ? $user->name : $user->email_address;

}

memoize 'resolve_user_id_to';

sub warp_list_to_old_value {
    my $self       = shift;
    my $task_value = shift || '';
    my $add        = shift;
    my $del        = shift;

    my @new = split( /\s*,\s*/, $task_value );
    my @old = grep { $_ ne $add } @new, $del;
    return join( ", ", @old );
}

our $MONNUM = {
    Jan => 1,
    Feb => 2,
    Mar => 3,
    Apr => 4,
    May => 5,
    Jun => 6,
    Jul => 7,
    Aug => 8,
    Sep => 9,
    Oct => 10,
    Nov => 11,
    Dec => 12
};


our %PROP_MAP = (
    subject         => 'summary',
    status          => 'status',
    owner           => 'owner',
    initialpriority => '_delete',
    finalpriority   => '_delete',
    told            => '_delete',
    requestors      => 'reported_by',
    admincc         => 'admin_cc',
    refersto        => 'refers_to',
    referredtoby    => 'referred_to_by',
    dependson       => 'depends_on',
    dependedonby    => 'depended_on_by',
    hasmember       => 'members',
    memberof        => 'member_of',
    priority        => 'priority_integer',
    resolved        => 'completed',
    due             => 'due',
    creator         => 'creator',
    timeworked      => 'time_worked',
    timeleft        => 'time_left',
    lastupdated     => '_delete',
    created         => '_delete',            # we should be porting the create date as a metaproperty

);

sub translate_prop_names {
    my $self      = shift;
    my $changeset = shift;

    for my $change ( $changeset->changes ) {
        next unless $change->node_type eq 'ticket';

        my @new_props;
        for my $prop ( $change->prop_changes ) {
            next if ( ( $PROP_MAP{ lc( $prop->name ) } || '' ) eq '_delete' );
            $prop->name( $PROP_MAP{ lc( $prop->name ) } ) if $PROP_MAP{ lc( $prop->name ) };

            if ( $prop->name eq 'id' ) {
                $prop->old_value( $prop->old_value . '@' . $changeset->original_source_uuid )
                    if ( $prop->old_value || '' ) =~ /^\d+$/;
                $prop->old_value( $prop->new_value . '@' . $changeset->original_source_uuid )
                    if ( $prop->new_value || '' ) =~ /^\d+$/;

            }

            if ( $prop->name =~ /^cf-(.*)$/ ) {
                $prop->name( 'custom-' . $1 );
            }

            push @new_props, $prop;

        }
        $change->prop_changes( \@new_props );

    }
    return $changeset;
}

1;
