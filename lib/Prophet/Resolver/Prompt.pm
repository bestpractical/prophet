use warnings;
use strict;

package Prophet::Resolver::Prompt;
use base qw/Prophet::Resolver/;

sub run {
    my $self               = shift;
    my $conflicting_change = shift;
    return 0 if $conflicting_change->file_op_conflict;

    my $resolution = Prophet::Change->new_from_conflict($conflicting_change);
    print "Oh no! There's a conflict between this replica and the one you're syncing from:\n";
    print $conflicting_change->record_type . " " . $conflicting_change->node_uuid . "\n";

    for my $prop_conflict ( @{ $conflicting_change->prop_conflicts } ) {

        print $prop_conflict->name . ": \n";
        print "(T)ARGET     " . $prop_conflict->target_value . "\n";
        print "SOURCE (O)LD " . $prop_conflict->source_old_value . "\n";
        print "SOURCE (N)EW " . $prop_conflict->source_new_value . "\n";

        while ( my $choice = lc( substr( <STDIN> || 'T', 0, 1 ) ) ) {

            if ( $choice eq 't' ) {

                $resolution->add_prop_change(
                    name => $prop_conflict->name,
                    old  => $prop_conflict->source_new_value,
                    new  => $prop_conflict->target_value
                );
                last;
            } elsif ( $choice eq 'o' ) {

                $resolution->add_prop_change(
                    name => $prop_conflict->name,
                    old  => $prop_conflict->source_new_value,
                    new  => $prop_conflict->source_old_value
                );
                last;

            } elsif ( $choice eq 'n' ) {
                last;

            } else {
                print "(T), (O) or (N)? ";
            }
        }
    }
    return $resolution;
}

1;

