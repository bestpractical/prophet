use warnings;
use strict;

package Prophet::Resolver::FromResolutionDB;
use base qw/Prophet::Resolver/;
use Prophet::Change;

sub run {
    my $self = shift;
    my $conflicting_change = shift;
    my $conflict = shift;
    my $resdb = shift;

    # XXX: turn this into an explicit load?
    $resdb->matching( sub { $_[0]->uuid eq $conflicting_change->cas_key });
    my $answer = $resdb->as_array_ref->[0] or return;
    
    my $resolution = Prophet::Change->new_from_conflict($conflicting_change);
    for my $prop_conflict ( @{ $conflicting_change->prop_conflicts } ) {
        $resolution->add_prop_change(
            name => $prop_conflict->name,
            old  => $prop_conflict->source_old_value,
            new  => $answer->prop( $prop_conflict->name ),
        );
    }
    return $resolution;

}

1;
