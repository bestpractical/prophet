package Prophet::Conflict;
use Any::Moose;
use Params::Validate;
use Prophet::ConflictingPropChange;
use Prophet::ConflictingChange;

has prophet_handle => (
    is  => 'rw',
    isa => 'Prophet::Replica',
);

has resolvers => (
    is         => 'rw',
    isa        => 'ArrayRef',
    default    => sub { [] },
    auto_deref => 1,
);

has changeset => (
    is  => 'rw',
    isa => 'Prophet::ChangeSet',
);

has nullification_changeset => (
    is  => 'rw',
    isa => 'Prophet::ChangeSet',
);

has resolution_changeset => (
    is  => 'rw',
    isa => 'Prophet::ChangeSet',
);

has autoresolved => (
    is  => 'rw',
    isa => 'Bool',
);

has conflicting_changes => (
    is        => 'ro',
    isa       => 'ArrayRef',
    default   => sub { [] },
);

sub has_conflicting_changes { scalar @{ $_[0]->conflicting_changes } }
sub add_conflicting_change  {
    my $self = shift;
    push @{ $self->conflicting_changes }, @_;
}

=head2 analyze_changeset Prophet::ChangeSet

Take a look at a changeset. if there are any conflicts, populate
the L<conflicting_changes> array on this object with a set of
L<Prophet::ConflictingChange> objects.

=cut

sub analyze_changeset {
    my $self = shift;

    #my ($changeset) = validate_pos( @_, { isa => 'Prophet::ChangeSet' } );

    $self->generate_changeset_conflicts();
    return unless $self->has_conflicting_changes;

    $self->generate_nullification_changeset;

    return 1;
}

use Prophet::Resolver::IdenticalChanges;
use Prophet::Resolver::FromResolutionDB;
use Prophet::Resolver::Failed;
use Prophet::Resolver::Prompt;

sub generate_resolution {
    my $self      = shift;
    my $resdb     = shift;
    my @resolvers = (
        sub { Prophet::Resolver::IdenticalChanges->new->run(@_); },
        $resdb ? sub { Prophet::Resolver::FromResolutionDB->new->run(@_) } : (),
        $self->resolvers,
        (-t STDIN && -t STDOUT) ? sub { Prophet::Resolver::Prompt->new->run(@_); } : (),
        sub { Prophet::Resolver::Failed->new->run(@_) },
    );
    my $resolutions = Prophet::ChangeSet->new({
        creator       => $self->prophet_handle->changeset_creator,
        is_resolution => 1,
    });
    for my $conflicting_change ( @{ $self->conflicting_changes } ) {
        for (@resolvers) {
            if ( my $resolution = $_->( $conflicting_change, $self, $resdb ) ) {
                $resolutions->add_change( change => $resolution ) if $resolution->has_prop_changes;
                last;
            }
        }
    }

    $self->resolution_changeset($resolutions);
    return 1;
}

=head2 generate_changeset_conflicts 

Given a changeset, populates $self->conflicting_changes with all the conflicts that applying that changeset to the target replica would result in.

=cut

sub generate_changeset_conflicts {
    my $self = shift;
    for my $change ( $self->changeset->changes ) {
        if ( my $change_conflicts = $self->_generate_change_conflicts($change) ) {
            $self->add_conflicting_change($change_conflicts);
        }
    }
}

=head2 _generate_change_conflicts Prophet::Change

Given a change, generates a set of Prophet::ConflictingChange entries.

=cut

sub _generate_change_conflicts {
    my $self = shift;
    my ($change) = validate_pos( @_, { isa => "Prophet::Change" } );
    my $file_op_conflict;

    my $file_exists = $self->prophet_handle->record_exists(
        uuid => $change->record_uuid,
        type => $change->record_type
    );

    # It's ok to delete a record that exists
    if ( $change->change_type eq 'delete' && !$file_exists ) {
        $file_op_conflict = "delete_missing_file";
    }
    elsif ( $change->change_type eq 'update_file' && !$file_exists ) {
        $file_op_conflict = "update_missing_file";
    }
    elsif ( $change->change_type eq 'add_file' && $file_exists ) {
        # we can recover from "Trying to add a file which exists" by converting it to an "update file"
        # operation. This should ONLY ever happen on settings conflicts
        $change->change_type('update_file');

    }
    elsif ( $change->change_type eq 'add_dir' && $file_exists ) {

        # XXX TODO: this isn't right
        $file_op_conflict = "create_existing_dir";
    }

    my $change_conflict = Prophet::ConflictingChange->new(
        {
            record_type          => $change->record_type,
            record_uuid          => $change->record_uuid,
            target_record_exists => ($file_exists ? 1 : 0 ),
            change_type          => $change->change_type,
            $file_op_conflict ? ( file_op_conflict => $file_op_conflict ) : (),
        }
    );

    if ($file_exists) {
        my $current_state = $self->prophet_handle->get_record_props(
            uuid => $change->record_uuid,
            type => $change->record_type
        );

        $change_conflict->add_prop_conflict(
            $self->_generate_prop_change_conflicts( $change, $current_state ) );
    }

    return ( $change_conflict->has_prop_conflicts || $file_op_conflict )
      ? $change_conflict
      : undef;
}

=head2 _generate_prop_change_conflicts Prophet::Change %hash_of_current_properties

Given a change and the current state of a record, returns an array of Prophet::ConflictingPropChange objects describing conflicts which would occur if the change were applied


=cut

sub _generate_prop_change_conflicts {
    my $self          = shift;
    my $change        = shift;
    my $current_state = shift;
    my @prop_conflicts;
    for my $prop_change ( $change->prop_changes ) {

        # skip properties added by the change
        next if ( !defined $current_state->{ $prop_change->name } && !defined $prop_change->old_value );

       # If either the old version didn't have a value or the delta didn't have a value, then we know there's a conflict
        my $s = {
            name             => $prop_change->name,
            source_old_value => $prop_change->old_value,
            target_value     => $current_state->{ $prop_change->name },
            source_new_value => $prop_change->new_value
        };

        my $old_exists =
          ( defined $prop_change->old_value && $prop_change->old_value ne '' )
          ? 1
          : 0;
        my $current_exists =
          exists $current_state->{ $prop_change->name }
          ? 1
          : 0;

        no warnings 'uninitialized';
        if ( 
               (  $current_exists != $old_exists)
            || ( $current_state->{ $prop_change->name } ne $prop_change->old_value ) )
        {
            push @prop_conflicts, Prophet::ConflictingPropChange->new($s);
        }

    }
    return @prop_conflicts;
}

=head2 generate_nullification_changeset

In order to record a changeset which might not apply cleanly to the
current state of a replica, Prophet generates a I<nullification
changeset>. That is, a changeset which sets the state of the replica
back to what it needs to be in order to apply the new changeset.

This routine computes a new L<Prophet::ChangeSet> which contains
everything needed to nullify the conflicting state of the replica.

=cut

sub generate_nullification_changeset {
    my $self = shift;
    my $nullification = Prophet::ChangeSet->new({
        is_nullification => 1,
        creator => undef,
        created => undef,
    });

    for my $conflict ( @{ $self->conflicting_changes } ) {
        my $nullify_conflict
            = Prophet::Change->new( { record_type => $conflict->record_type, record_uuid => $conflict->record_uuid } );

        my $file_op_conflict = $conflict->file_op_conflict || '';
        if ( $file_op_conflict eq "delete_missing_file" ) {
            $nullify_conflict->change_type('add_file');
        } elsif ( $file_op_conflict eq "update_missing_file" ) {
            $nullify_conflict->change_type('add_file');
        } elsif ( $file_op_conflict eq "create_existing_file" ) {
            $nullify_conflict->change_type('delete');
        } elsif ( $file_op_conflict ) {
            die "We don't know how to deal with a conflict of type " . $conflict->file_op_conflict;
        } else {
            $nullify_conflict->change_type('update_file');
        }

        # now that we've sorted out all the file-level conflicts, we need to get properties in order
        for my $prop_conflict ( @{ $conflict->prop_conflicts } ) {
            $nullify_conflict->add_prop_change(
                name => $prop_conflict->name,
                old  => $prop_conflict->target_value,
                new  => $prop_conflict->source_old_value
            );
        }
        $nullification->add_change( change => $nullify_conflict );
    }

    $self->nullification_changeset($nullification);
}

__PACKAGE__->meta->make_immutable;
no Any::Moose;

1;

