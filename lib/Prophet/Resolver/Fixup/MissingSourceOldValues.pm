package Prophet::Resolver::Fixup::MissingSourceOldValues;
use Any::Moose;
extends 'Prophet::Resolver';

sub run {
    my $self               = shift;
    my $conflicting_change = shift;
    return 0 if $conflicting_change->file_op_conflict;

    my $resolution = Prophet::Change->new_from_conflict($conflicting_change);
    for my $prop_conflict ( @{ $conflicting_change->prop_conflicts } ) {

        if ( defined $prop_conflict->source_old_value 
            && $prop_conflict->source_old_value ne '' ) {
            return 0;
        }

        #$resolution->add_prop_change( name => $prop_conflict->name, old  => $prop_conflict->target_value, new  => $prop_conflict->source_new_value);
    }
    return $resolution;
}

__PACKAGE__->meta->make_immutable;
no Any::Moose;

1;

