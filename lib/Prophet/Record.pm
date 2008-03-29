
use warnings;
use strict;
package Prophet::Record;
use Params::Validate;
use Prophet::HistoryEntry;
use base qw'Class::Accessor';
__PACKAGE__->mk_accessors(qw'handle props uuid type');
my $UUIDGEN = Data::UUID->new();

sub new {
    my $class = shift;
    my $self = {};
    bless $self, $class;
    my %args = validate(@_, { handle => 1, type => 1});
    $self->$_($args{$_}) for keys(%args);
    return $self;
}

sub create {
    my $self = shift;
    my %args = validate(@_, {  props => 1});

    $self->uuid($UUIDGEN->create_str);


    $self->_canonicalize_props($args{'props'});
    $self->_validate_props($args{'props'}) || return undef;

    $self->handle->create_node( props => $args{'props'}, uuid => $self->uuid, type => $self->type);

    return $self->uuid;
}





sub load {
    my $self = shift;
    my %args = validate(@_, { uuid => 1});
    $self->uuid($args{uuid});

}

sub set_prop {
    my $self = shift;

    my %args = validate(@_, { name => 1, value => 1});
    my $props = { $args{'name'} => $args{'value'}};
    $self->set_props(props => $props);
}


sub set_props {
    my $self = shift;
    my %args = validate(@_, { props => 1});

    $self->_canonicalize_props($args{'props'});
    $self->_validate_props($args{'props'}) || return undef;
    $self->handle->set_node_props(type => $self->type, uuid => $self->uuid, props => $args{'props'} );
}




sub get_props {
    my $self = shift;
    return $self->handle->get_node_props(uuid => $self->uuid, type => $self->type);
}

sub prop {
    my $self = shift;
    my $prop = shift;
    return $self->get_props->{$prop};
}


sub delete_prop {
    my $self = shift;
    my %args = validate(@_, { name => 1});
    $self->handle->delete_node_prop(uuid => $self->uuid, name => $args{'name'});
}

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

sub storage_node {
    my $self = shift;
    return $self->handle->file_for(type => $self->type, uuid => $self->uuid);
}



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
