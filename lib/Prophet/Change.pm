use warnings;
use strict;

package Prophet::Change;
use base qw/Class::Accessor/;

use Prophet::PropChange;
use Params::Validate;
__PACKAGE__->mk_accessors(qw/record_type node_uuid change_type resolution_cas/);

=head1 NAME

Prophet::Change

=head1 DESCRIPTION

This class encapsulates a change to a single node in a Prophet replica.

=head1 METHODS

=head2 record_type

The record type for the node.

=head2 node_uuid

The UUID of the node being changed

=head2 change_type

One of create_file, add_dir, update_file, delete
XXX TODO is it create_file or add_file?

=head2 prop_changes [\@PROPCHANGES]

Returns a list of L<Prophet::PropChange/> associated with this Change. Takes an optional arrayref to fully replace the set of propcahnges

=cut

sub prop_changes {
    my $self = shift;
    $self->{prop_changes} = shift if @_;
    return @{ $self->{prop_changes} || [] };
}

=head2 new_from_conflict( $conflict )

=cut

sub new_from_conflict {
    my ( $class, $conflict ) = @_;
    my $self = $class->new(
        {   is_resolution  => 1,
            resolution_cas => $conflict->cas_key,
            change_type    => $conflict->change_type,
            record_type      => $conflict->record_type,
            node_uuid      => $conflict->node_uuid
        }
    );
    return $self;
}

=head2 add_prop_change { new => __, old => ___, name => ___ }

Adds a new L<Prophet::PropChange> to this L<Prophet::Change>.

Takes a C<name>, and the C<old> and C<new> values.

=cut

sub add_prop_change {
    my $self   = shift;
    my %args   = validate( @_, { name => 1, old => 0, new => 0 } );
    my $change = Prophet::PropChange->new();
    $change->name( $args{'name'} );
    $change->old_value( $args{'old'} );
    $change->new_value( $args{'new'} );

    push @{ $self->{prop_changes} }, $change;

}

sub as_hash {
    my $self  = shift;
    my $props = {};
    for my $pc ( $self->prop_changes ) {
        $props->{ $pc->name } = { old_value => $pc->old_value, new_value => $pc->new_value };
    }

    return {
        record_type    => $self->record_type,
        change_type  => $self->change_type,
        prop_changes => $props

    };
}

sub new_from_hashref {
    my $class   = shift;
    my $uuid    = shift;
    my $hashref = shift;
    my $self    = $class->new(
        { record_type => $hashref->{'record_type'}, node_uuid => $uuid, change_type => $hashref->{'change_type'} } );
    foreach my $prop ( keys %{ $hashref->{'prop_changes'} } ) {
        $self->add_prop_change(
            name => $prop,
            old  => $hashref->{'prop_changes'}->{$prop}->{'old_value'},
            new  => $hashref->{'prop_changes'}->{$prop}->{'new_value'}
        );
    }
    return $self;
}

1;
