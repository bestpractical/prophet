use warnings;
use strict;

package Prophet::Record;

=head1 NAME

Prophet::Record

=head1 DESCRIPTION

This class represents a base class for any record in a Prophet database

=cut


use base qw'Class::Accessor';

__PACKAGE__->mk_accessors(qw'handle props uuid type');

use Params::Validate;
use Prophet::HistoryEntry;

my $UUIDGEN = Data::UUID->new();

=head1 METHODS

=head2 new  { handle => Prophet::Handle, type => $type }

Instantiates a new, empty L<Prophet::Record/> of type $type.

=cut


sub new {
    my $class = shift;
    my $self = bless {}, $class;
    my %args = validate(@_, { handle => 1, type => 1});
    $self->$_($args{$_}) for keys(%args);
    return $self;
}

=head2 create { props => { %hash_of_kv_pairs } }

Creates a new Prophet database record in your database. Sets the record's properties to the keys and values passed in.

Automatically canonicalizes and then validates the props.

Upon successful creation, returns the new record's C<uuid>.
In case of failure, returns undef.

=cut

sub create {
    my $self = shift;
    my %args = validate(@_, {  props => 1});
        my $uuid = $UUIDGEN->create_str;

    $self->uuid($uuid);

    $self->_canonicalize_props($args{'props'});
    $self->_validate_props($args{'props'}) || return undef;
    $self->handle->create_node( props => $args{'props'}, uuid => $self->uuid, type => $self->type);
    return $self->uuid;
}


=head2 load { uuid => $UUID }

Loads a Prophet record off disk by its uuid.

=cut


sub load {
    my $self = shift;
    my %args = validate(@_, { uuid => 1});
    $self->uuid($args{uuid});

}


=head2 set_prop { name => $name, value => $value }

Updates the current record to set an individual property called C<$name> to C<$value>

This is a convenience method around L</set_props>.

=cut

sub set_prop {
    my $self = shift;

    my %args = validate(@_, { name => 1, value => 1});
    my $props = { $args{'name'} => $args{'value'}};
    $self->set_props(props => $props);
}

=head2 set_props { props => { key1 => val1, key2 => val2} }

Updates the current record to set all the keys contained in the C<props> parameter to their associated values.
Automatically canonicalizes and validates the props in question.

In case of failure, returns false.

On success, returns ____

=cut


sub set_props {
    my $self = shift;
    my %args = validate(@_, { props => 1});

    $self->_canonicalize_props($args{'props'});
    $self->_validate_props($args{'props'}) || return undef;
    $self->handle->set_node_props(type => $self->type, uuid => $self->uuid, props => $args{'props'} );
}


=head2 get_props

Returns a hash of this record's properties as currently set in the database.

=cut

sub get_props {
    my $self = shift;
    return $self->handle->get_node_props(uuid => $self->uuid, type => $self->type);
}

=head2 prop $name

Returns the current value of the property C<$name> for this record. 
(This is a convenience method wrapped around L</get_props>.

=cut

sub prop {
    my $self = shift;
    my $prop = shift;
    return $self->get_props->{$prop};
}

=head2 delete_prop { name => $name }

Deletes the current value for the property $name. 

TODO: how is this different than setting it to an empty value?

=cut

sub delete_prop {
    my $self = shift;
    my %args = validate(@_, { name => 1});
    $self->handle->delete_node_prop(uuid => $self->uuid, name => $args{'name'});
}

=head2 delete

Deletes this record from the database. (Note that it does _not_ purge historical versions of the record)

=cut

sub delete {
    my $self = shift;
    $self->handle->delete_node(type => $self->type, uuid => $self->uuid);

}

sub _validate_props {
    my $self = shift;
    my $props = shift;
    my $errors = {};
    for my $key (keys %$props) {
        return undef unless ($self->_validate_prop_name($key));
        if (my $sub = $self->can('validate_'.$key)) { 
            $sub->($self, props => $props, errors => $errors) || return undef;
        }
    }
    return 1;
}


sub _validate_prop_name { 1}

sub _canonicalize_props {
    my $self = shift;
    my $props = shift;
    my $errors = {};
    for my $key (keys %$props) {
        if (my $sub = $self->can('canonicalize_'.$key)) { 
            $sub->($self, props => $props, errors => $errors);
        }
    }
    return 1;
}

=head2 storage_node

Returns the path of this node within the Prophet repository. (Really, it delegates this to L<Prophet::Handle/file_for>.

=cut

sub storage_node {
    my $self = shift;
    return $self->handle->file_for(type => $self->type, uuid => $self->uuid);
}


=head2 history

Returns an array of L<Prophet::HistoryEntry> objects ordered from oldest to newest. It is important to note that Prophet's merge algorithms guarantee that _local_ record history will never be reordered but that different replicas will often have different history orderings based on when replicas were merged or synced.

=cut

sub history {
    my $self       = shift;
    my $oldest_rev = 0;
    my @history;
    $self->handle->repo_handle->get_logs(
        [ $self->storage_node ],
        $self->handle->repo_handle->fs->youngest_rev,
        $oldest_rev,
        1,
        0,
        sub { $self->_history_entry_callback( \@history, @_ ) }
    );
    $self->_compute_history_deltas(\@history);
    return \@history;
}


sub _history_entry_callback {
    my $self = shift;
    my ( $accumulator, $paths, $rev, $author, $date, $msg ) = @_;
    my @nodes = keys %$paths;
    die "We should only have one node!" unless ( $#nodes == 0 );

    my $node = $paths->{ $nodes[0] };
    my $data = Prophet::HistoryEntry->new( handle => $self->handle );

    $data->rev($rev);
    $data->author($author);
    $data->date($date);
    $data->msg($msg);
    $data->action( $node->action() );
    $data->copy_from( $node->copyfrom_path() );
    $data->copy_from_rev( $node->copyfrom_rev() );
    $data->props( $self->handle->repo_handle->fs()->revision_root($rev)->node_proplist( $nodes[0] ) );

    push @$accumulator, $data;
}

sub _compute_history_deltas {
    my $self    = shift;
    my $log_ref = shift;
    @$log_ref = reverse @$log_ref;
    my $last_props = {};
    for my $i ( 0 .. $#{$log_ref} ) {

        my $props = $log_ref->[$i]->props;

        for my $key ( keys %$props ) {

            if ( !exists $last_props->{$key} ) {
                $log_ref->[$i]->prop_changes->{$key}->{'add'}
                    = $props->{$key};
            } elsif ( $last_props->{$key} ne $props->{$key} ) {
                $log_ref->[$i]->prop_changes->{$key}->{'add'}
                    = $props->{$key};
                $log_ref->[$i]->prop_changes->{$key}->{'del'}
                    = $last_props->{$key};
            }
        }
        foreach my $key ( keys %$last_props ) {
            if ( !exists $props->{$key} ) {
                $log_ref->[$i]->prop_changes->{$key}->{'del'}
                    = $last_props->{$key};
            }
        }

        $last_props = $props;
    }

    return $log_ref;

}
1;
