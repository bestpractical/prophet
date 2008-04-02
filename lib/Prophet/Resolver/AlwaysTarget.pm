use warnings;
use strict;

package Prophet::Resolver::AlwaysTarget;
use base qw/Prophet::Resolver/;


sub  run {
    my $self = shift;
 my $conflict = shift;
            return 0 if $conflict->file_op_conflict;

            my $resolution = Prophet::Change->new_from_conflict( $conflict );

            for my $prop_conflict ( @{ $conflict->prop_conflicts } ) {
                $resolution->add_prop_change(
                    name => $prop_conflict->name,
                    old  => $prop_conflict->source_old_value,
                    new  => $prop_conflict->target_value
                );
            }
            return $resolution;
}

1;

