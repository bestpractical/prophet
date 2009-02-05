package Prophet::Resolver::AlwaysTarget;
use Any::Moose;
use Data::Dumper;
extends 'Prophet::Resolver';

sub run {
    my $self               = shift;
    my $conflicting_change = shift;
    my $conflict           = shift;
    my $resolution         = Prophet::Change->new_from_conflict($conflicting_change);
    my $file_op_conflict = $conflicting_change->file_op_conflict || '';
    if ( $file_op_conflict eq 'update_missing_file' ) {
        $resolution->change_type('delete');
        return $resolution;
    } elsif ( $file_op_conflict eq 'delete_missing_file' ) {
        return $resolution;
    } elsif ( $file_op_conflict ) {
        die "Unknown file_op_conflict $file_op_conflict: " . Dumper($conflict,$conflicting_change);
    }

    for my $prop_change ( @{ $conflicting_change->prop_conflicts } ) {
        $resolution->add_prop_change(
            name => $prop_change->name,
            old  => $prop_change->source_new_value,
            new  => $prop_change->target_value
        );
    }
    return $resolution;
}

__PACKAGE__->meta->make_immutable;
no Any::Moose;

1;

