use warnings;
use strict;

package Prophet::Resolver::AlwaysTarget;
use base qw/Prophet::Resolver/;

sub run {
    my $self               = shift;
    my $conflicting_change = shift;
    my $conflict           = shift;
    my $resolution         = Prophet::Change->new_from_conflict($conflicting_change);
    if ( $conflicting_change->file_op_conflict eq 'update_missing_file' ) {
        $resolution->change_type('delete');
        return $resolution;
    } elsif ( $conflicting_change->file_op_conflict eq 'delete_missing_file' ) {
        return $resolution;
    } elsif ( $conflicting_change->file_op_conflict ) {
        die YAML::Dump( $conflict, $conflicting_change );
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

1;

